"""Optional developer-only comparison of a pinned public Sony capture pair.

Requires rawpy, numpy and scipy. No demosaic, WB, tone curve or correction is
applied. Locally align same-CFA-channel patches before reporting signal gain
and relative R/B motion. This is observation, not a product calibration.
"""
from pathlib import Path
import hashlib
import json
import platform
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'Build/Development/sony-public-pair'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    import numpy as np
    import rawpy
    import scipy
    from scipy.ndimage import gaussian_filter, map_coordinates, shift, spline_filter
    from scipy.optimize import least_squares
    from scipy.signal import fftconvolve

    fixture_path = ROOT / 'Tests/Fixtures/Sony-recorded-settings.json'
    fixture = json.loads(fixture_path.read_text())
    pair = [next(x for x in fixture['files'] if x['repositoryEntry'] == entry) for entry in [1315, 1318]]
    mosaics, records = [], []
    for item in pair:
        path = ROOT / 'Tests/PrivateRAW' / item['file']
        if not path.is_file() or digest(path) != item['sha256']:
            raise SystemExit('Pinned public RAW absent or changed; no pair conclusion generated.')
        command = ['/usr/bin/perl', str(ROOT / 'Resources/LensBridge/exiftool/exiftool'), '-j', '-G1', '-n',
                   '-IFD0:Model', '-ExifIFD:LensModel', '-ExifIFD:FocalLength', '-ExifIFD:FNumber',
                   '-ExifIFD:ExposureTime', '-ExifIFD:ISO', '-SubIFD:DistortionCorrection',
                   '-SubIFD:ChromaticAberrationCorrection', '-SubIFD:VignettingCorrection',
                   '-SubIFD:DistortionCorrParams', '-SubIFD:ChromaticAberrationCorrParams',
                   '-SubIFD:VignettingCorrParams', str(path)]
        metadata = json.loads(subprocess.check_output(command, timeout=30))[0]
        metadata.pop('SourceFile', None)
        with rawpy.imread(str(path)) as raw:
            mosaic = raw.raw_image_visible.copy()
            record = {'fixture': item['file'], 'sha256': item['sha256'], 'repositoryEntry': item['repositoryEntry'],
                      'metadata': metadata, 'librawSizes': raw.sizes._asdict(), 'cfa': raw.raw_pattern.tolist(),
                      'blackPerChannel': raw.black_level_per_channel, 'whiteLevel': raw.white_level}
        mosaics.append(mosaic)
        records.append(record)
    for key in ['IFD0:Model', 'ExifIFD:LensModel', 'ExifIFD:FocalLength', 'ExifIFD:FNumber',
                'ExifIFD:ExposureTime', 'ExifIFD:ISO', 'SubIFD:DistortionCorrection',
                'SubIFD:DistortionCorrParams', 'SubIFD:ChromaticAberrationCorrParams', 'SubIFD:VignettingCorrParams']:
        if records[0]['metadata'].get(key) != records[1]['metadata'].get(key):
            raise SystemExit('Pair does not have equal recorded exposure/optical conditions and source tables.')
    if records[0]['metadata'].get('SubIFD:VignettingCorrection') != 257 or records[1]['metadata'].get('SubIFD:VignettingCorrection') != 256:
        raise SystemExit('Actual menu-state pair changed; filenames are not the state oracle.')
    if records[0]['cfa'] != records[1]['cfa'] or mosaics[0].shape != mosaics[1].shape:
        raise SystemExit('Pair pixel layout differs.')

    radius, search_radius = 24, 8
    yy, xx = np.mgrid[-radius:radius+1, -radius:radius+1]

    def match(target, source, rows=9, columns=13):
        cubic = spline_filter(source, order=3)
        pad = radius + search_radius
        output = []
        for row, y in enumerate(np.linspace(pad+2, target.shape[0]-pad-3, rows).astype(int)):
            for col, x in enumerate(np.linspace(pad+2, target.shape[1]-pad-3, columns).astype(int)):
                patch = target[y-radius:y+radius+1, x-radius:x+radius+1]
                search = source[y-pad:y+pad+1, x-pad:x+pad+1]
                centered = patch-patch.mean()
                energy = np.sum(centered**2)
                if np.std(patch) < .01 or np.mean((patch > .01) & (patch < .95)) < .95:
                    continue
                ones = np.ones_like(patch)
                sums = fftconvolve(search, ones, mode='valid')
                variance = np.maximum(fftconvolve(search**2, ones, mode='valid')-sums*sums/patch.size, 0)
                ncc = fftconvolve(search, centered[::-1, ::-1], mode='valid') / np.sqrt(np.maximum(variance*energy, 1e-24))
                py, px = np.unravel_index(np.argmax(ncc), ncc.shape)
                peak = float(ncc[py, px])
                if min(px, py) == 0 or px == ncc.shape[1]-1 or py == ncc.shape[0]-1:
                    continue
                rest = ncc.copy()
                rest[max(0,py-3):py+4, max(0,px-3):px+4] = -1
                if peak < .98 or peak-float(rest.max()) < .02:
                    continue
                unit_patch = centered / np.sqrt(energy)

                def sample(p):
                    return map_coordinates(cubic, [y+p[1]+yy+p[4]*xx+p[5]*yy,
                                                   x+p[0]+xx+p[2]*xx+p[3]*yy], order=3, prefilter=False)

                def residual(p):
                    image = sample(p)
                    image -= image.mean()
                    return (image/max(np.linalg.norm(image),1e-12)-unit_patch).ravel()

                initial = np.array([px-search_radius, py-search_radius, 0., 0., 0., 0.])
                fit = least_squares(residual, initial, bounds=(initial-[2,2,.04,.04,.04,.04], initial+[2,2,.04,.04,.04,.04]),
                                    max_nfev=40, ftol=1e-8, xtol=1e-7, gtol=1e-7)
                refined = float(1-.5*np.sum(residual(fit.x)**2))
                if not fit.success or refined < .995:
                    continue
                aligned = sample(fit.x)
                gain = float(np.sum(centered*(aligned-aligned.mean()))/energy)
                offset = float(aligned.mean()-gain*patch.mean())
                radius_at_center = float(np.hypot((x+.5)/target.shape[1]-.5, (y+.5)/target.shape[0]-.5)/np.hypot(.5,.5))
                output.append({'grid': [row,col], 'normalizedHalfDiagonalRadius': radius_at_center,
                               'sourceOnMinusTargetOffPixels': [float(2*fit.x[0]),float(2*fit.x[1])],
                               'refinedNCC': refined, 'gainOnVersusOff': gain, 'normalizedOffset': offset})
        return output

    observations = []
    controls = []
    for cy in range(2):
        for cx in range(2):
            color = records[0]['cfa'][cy][cx]
            planes = [(m[cy::2,cx::2].astype(np.float64)-r['blackPerChannel'][color])/
                      (r['whiteLevel']-r['blackPerChannel'][color]) for m,r in zip(mosaics,records)]
            on, off = planes
            # First slot controls establish subpixel direction/gain independently
            # of the observed pair, using a compact deterministic texture.
            if cy == 0 and cx == 0:
                # A band-limited, deterministic texture gives a known control
                # independently of whichever natural patches this pair contains.
                rng = np.random.default_rng(217)
                control_source = gaussian_filter(rng.normal(size=(600,900)),2)
                control_source = .4+.06*control_source/np.std(control_source)
                identity = match(control_source, control_source, 4, 5)
                moved = shift(control_source, (.35,-.6), order=3, mode='constant')*1.07+.003
                synthetic = match(control_source, moved, 4, 5)
                for name, points, expected_shift, expected_gain in [('identity',identity,[0.,0.],1.),
                                                                  ('known-affine',synthetic,[-1.2,.7],1.07)]:
                    errors = [float(np.linalg.norm(np.array(p['sourceOnMinusTargetOffPixels'])-expected_shift)) for p in points]
                    gain_errors = [abs(p['gainOnVersusOff']-expected_gain) for p in points]
                    passed = len(points)>=8 and max(errors,default=100)<.1 and max(gain_errors,default=100)<.01
                    controls.append({'name':name,'accepted':len(points),'maximumPositionErrorRawPixels':max(errors,default=None),
                                     'maximumGainError':max(gain_errors,default=None),'passed':passed})
                    if not passed:
                        raise SystemExit('Registration control failed; no pair inference generated: '+json.dumps(controls))
            points = match(off, on)
            center_gains = [p['gainOnVersusOff'] for p in points if p['normalizedHalfDiagonalRadius']<.3]
            center = float(np.median(center_gains)) if center_gains else None
            bins = []
            for lo,hi in [(0,.3),(.3,.6),(.6,.8),(.8,1.01)]:
                selected = [p for p in points if lo<=p['normalizedHalfDiagonalRadius']<hi]
                gains = [p['gainOnVersusOff']/center for p in selected] if center else []
                bins.append({'radiusRange':[lo,hi],'accepted':len(selected),'medianGainRelativeToCenter':float(np.median(gains)) if gains else None,
                             'p10p90':np.quantile(gains,[.1,.9]).tolist() if gains else None})
            observations.append({'cfaSlot':[cy,cx],'colorIndex':color,'acceptedPatches':len(points),'centerGainOnVersusOff':center,'radialBins':bins,'patches':points})
            print(f'CFA {cy},{cx}: {len(points)} accepted registered patches.',flush=True)

    relative = []
    by_slot = [{tuple(p['grid']):p for p in x['patches']} for x in observations]
    for grid in sorted(set.intersection(*(set(x) for x in by_slot))):
        common_green = np.mean([by_slot[1][grid]['sourceOnMinusTargetOffPixels'],by_slot[2][grid]['sourceOnMinusTargetOffPixels']],axis=0)
        relative.append({'grid':list(grid),'radius':by_slot[0][grid]['normalizedHalfDiagonalRadius'],
                         'redMinusGreenChangeRawPixels':(np.array(by_slot[0][grid]['sourceOnMinusTargetOffPixels'])-common_green).tolist(),
                         'blueMinusGreenChangeRawPixels':(np.array(by_slot[3][grid]['sourceOnMinusTargetOffPixels'])-common_green).tolist()})
    unchanged = all(digest(ROOT/'Tests/PrivateRAW'/x['file']) == x['sha256'] for x in pair)
    report = {'scope':'One public Sony same-exposure capture pair, raw Bayer planes before demosaic/WB/tone/decoder lens corrections. Registered patches observe signal gain and relative channel motion; not a calibrated flat field, controlled optical bench, proof across cameras or product correction model.',
              'records':records,'controls':controls,'observationScale':'One sample per Bayer color cell, half native axis resolution; reported displacements are original raw pixels.',
              'method':{'patchPlanePixels':49,'searchRadiusPlanePixels':8,'grid':[9,13],'minimumInitialNCC':.98,'minimumRefinedNCC':.995,
                        'localModel':'Unconstrained-by-lens local affine registration and fitted gain/intercept. Selection uses texture/NCC only, not observed gain or any lens curve.'},
              'observations':observations,'commonGridChannelChanges':relative,'rawsUnchanged':unchanged,
              'limitations':['Camera motion, scene/light changes, CFA interpolation and local alignment can bias signal and channel comparisons.',
                             'The pair changes vignetting and CA menu states together, not independently.',
                             'A recorded Auto/Off state is not itself evidence of whether data was corrected.',
                             'No optical gain or displacement from this scene is used in the product.'],
              'provesBakedCorrectionAcrossModels':False,'enablesAutomaticCorrection':False,
              'environment':{'macOS':platform.mac_ver()[0],'numpy':np.__version__,'scipy':scipy.__version__,'rawpy':rawpy.__version__,'libraw':list(rawpy.libraw_version)},
              'sourceSHA256':{str(Path(__file__).relative_to(ROOT)):digest(Path(__file__)),'Tests/Fixtures/Sony-recorded-settings.json':digest(fixture_path)}}
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'registered-mosaic-observation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print('Registered RAW pair observation saved; no product calibration generated.',flush=True)


if __name__ == '__main__':
    main()
