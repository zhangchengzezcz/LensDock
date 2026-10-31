"""Optional developer observation of two locally exported Lightroom PNGs.

Requires numpy, scipy and Pillow, never used by the product. The exports must
come from the same pinned public RAW and differ only in profile geometry.
No Adobe profile data or image is copied into distributable resources.
This measures agreement with one Adobe rendering, not optical ground truth.
"""
from pathlib import Path
import argparse
import hashlib
import json
import platform
import subprocess

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'Build/Development/LR-Optical-Reference'
EXPECTED = {
    'Baseline-built-in-CA': '8a1e65f39f873281ad6b5601edacd1a857a06f7d84720bc0426bbbcef50b75eb',
    'Geometry-D100-V0': '2261cc681f58372d0aa7d1c7dffd090b74b66faca37621f4ad4709bd45d875ad',
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    import numpy as np
    import scipy
    from scipy.signal import fftconvolve
    from scipy.ndimage import shift, spline_filter, map_coordinates
    from scipy.optimize import least_squares
    from PIL import Image, __version__ as pillow_version

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scale',type=float,choices=[.25,.5],default=.25)
    scale = parser.parse_args().scale
    radius, search_radius = int(80*scale), int(168*scale)
    failures = []
    images, exports = [], []
    for name, checksum in EXPECTED.items():
        path = WORK / 'Exports' / name / 'ILCE-6000.png'
        if not path.is_file() or digest(path) != checksum:
            raise SystemExit('Missing or changed reference export; reacquire and inspect before updating hashes.')
        command = ['/usr/bin/perl', str(ROOT / 'Resources/LensBridge/exiftool/exiftool'), '-j', '-G1', '-n',
                   '-ImageWidth', '-ImageHeight', '-BitDepth', '-ProfileDescription', '-LensProfileEnable',
                   '-LensProfileName', '-LensProfileDistortionScale', '-LensProfileVignettingScale',
                   '-AutoLateralCA', '-CropConstrainToWarp', '-HasCrop', str(path)]
        metadata = json.loads(subprocess.check_output(command, timeout=30))[0]
        metadata.pop('SourceFile', None)
        if (metadata.get('PNG:ImageWidth'), metadata.get('PNG:ImageHeight'), metadata.get('PNG:BitDepth')) != (6000, 4000, 16):
            raise SystemExit('Unexpected export pixel contract.')
        if metadata.get('XMP-crs:AutoLateralCA') != 0 or metadata.get('XMP-crs:HasCrop') is not False:
            raise SystemExit('Unexpected ordinary CA/crop state.')
        enabled = name == 'Geometry-D100-V0'
        if metadata.get('XMP-crs:LensProfileEnable') != int(enabled):
            raise SystemExit('Profile state does not match the acquisition label.')
        if enabled and (metadata.get('XMP-crs:LensProfileDistortionScale'), metadata.get('XMP-crs:LensProfileVignettingScale')) != (100, 0):
            raise SystemExit('Geometry export is not D100/V0.')
        with Image.open(path) as image:
            # 8-bit reduced luminance is used for spatial registration only.
            # Original 16-bit files remain untouched. This is not a color test.
            gray = np.asarray(image.convert('RGB').resize((int(6000*scale), int(4000*scale)), Image.Resampling.LANCZOS), dtype=np.float64).mean(axis=2) / 255
        images.append(gray)
        exports.append({'label': name, 'sha256': checksum, 'bytes': path.stat().st_size, 'metadata': metadata})

    def observations(target, source):
        records = []
        cubic_source = spline_filter(source, order=3)
        yy, xx = np.mgrid[-radius:radius+1, -radius:radius+1]
        pad = radius + search_radius
        for row, y in enumerate(np.linspace(pad + 2, target.shape[0] - pad - 3, 11).astype(int)):
            for col, x in enumerate(np.linspace(pad + 2, target.shape[1] - pad - 3, 17).astype(int)):
                patch = target[y-radius:y+radius+1, x-radius:x+radius+1]
                search = source[y-pad:y+pad+1, x-pad:x+pad+1]
                centered = patch - patch.mean()
                energy = np.sum(centered * centered)
                if energy < .003:
                    continue
                ones = np.ones_like(patch)
                sums = fftconvolve(search, ones, mode='valid')
                variance = np.maximum(fftconvolve(search * search, ones, mode='valid') - sums * sums / patch.size, 0)
                correlation = fftconvolve(search, centered[::-1, ::-1], mode='valid') / np.sqrt(np.maximum(variance * energy, 1e-24))
                py, px = np.unravel_index(np.argmax(correlation), correlation.shape)
                if min(px, py) == 0 or px == correlation.shape[1]-1 or py == correlation.shape[0]-1:
                    continue
                peak = float(correlation[py, px])
                # Reject a second unrelated matching feature, outside the local
                # peak basin. Neither fit residual nor candidate model selects points.
                rest = correlation.copy()
                rest[max(0,py-4):py+5,max(0,px-4):px+5] = -1
                margin = peak - float(rest.max())
                def subpixel(a, b, c):
                    return float(np.clip(.5 * (a-c) / (a-2*b+c), -.75, .75)) if a-2*b+c < -1e-12 else 0.
                dx = px-search_radius+subpixel(correlation[py,px-1],peak,correlation[py,px+1])
                dy = py-search_radius+subpixel(correlation[py-1,px],peak,correlation[py+1,px])
                accepted = peak >= .97 and margin >= .015
                refined_ncc = None
                if accepted:
                    # Local affine alignment accounts for the change in scale
                    # within a patch. Its center estimates the displacement;
                    # this does not use the Sony or Adobe correction model.
                    unit_patch = centered / np.sqrt(energy)
                    def residual(p):
                        sampled = map_coordinates(cubic_source,
                            [y+p[1]+yy+p[4]*xx+p[5]*yy, x+p[0]+xx+p[2]*xx+p[3]*yy],
                            order=3, prefilter=False)
                        sampled -= sampled.mean()
                        return (sampled / max(np.linalg.norm(sampled),1e-12)-unit_patch).ravel()
                    initial = np.array([dx,dy,0,0,0,0])
                    fit = least_squares(residual,initial,
                        bounds=(initial- [2.5,2.5,.08,.08,.08,.08],initial+[2.5,2.5,.08,.08,.08,.08]),
                        max_nfev=40,ftol=1e-9,xtol=1e-7,gtol=1e-7)
                    dx,dy = map(float,fit.x[:2])
                    refined_ncc = float(1-.5*np.sum(residual(fit.x)**2))
                    accepted = bool(fit.success and refined_ncc >= .985)
                records.append({'grid': [row,col], 'outputPixelCenter': [(x+.5)/scale,(y+.5)/scale],
                                'sourcePixelCenter': [(x+.5+dx)/scale,(y+.5+dy)/scale],
                                'ncc': peak, 'peakMargin': margin, 'refinedNCC':refined_ncc,'accepted':accepted})
        return records

    baseline, corrected = images
    controls = []
    for name, control, expected in [('identity',baseline,[0.,0.]),
                                     ('known-shift',shift(baseline,(3.5,-5.25),order=3,mode='constant'),[5.25/scale,-3.5/scale])]:
        points = observations(control, baseline)
        accepted = [p for p in points if p['accepted']]
        errors = [np.linalg.norm(np.subtract(p['sourcePixelCenter'],p['outputPixelCenter'])-expected) for p in accepted]
        okay = len(errors) >= 30 and float(np.percentile(errors,95)) < .6
        if not okay:
            failures.append(name + ' registration control failed')
        controls.append({'name':name,'expectedSourceMinusOutputOriginalPixels':expected,'accepted':len(accepted),
                         'p95ErrorOriginalPixels':float(np.percentile(errors,95)) if errors else None,'passed':okay})

    points = observations(corrected,baseline)
    accepted = [p for p in points if p['accepted']]
    if len(accepted) < 45:
        failures.append('Insufficient independent high-confidence patches')
    if failures:
        raise SystemExit(json.dumps({'failures':failures,'controls':controls,'accepted':len(accepted)}))
    q = np.array([p['outputPixelCenter'] for p in accepted])
    measured = np.array([p['sourcePixelCenter'] for p in accepted])
    # Checkerboard holdout is fixed before fitting; no residual-based rejection.
    train = np.array([(sum(p['grid']) % 2) == 0 for p in accepted])
    validate = ~train
    if min(sum(train),sum(validate)) < 15:
        raise SystemExit('Insufficient spatial holdout.')
    center = np.array([3000.,2000.])
    fixture = json.loads((ROOT/'Tests/Fixtures/Sony-embedded-metadata.json').read_text())['files'][0]
    words = list(map(int,fixture['expectedGroupedFields']['SubIFD:DistortionCorrParams'].split()))
    n = words[0]
    nodes = np.array(words[1:n+1],dtype=float) / 16384 + 1
    candidates = [('identity-plus-isotropic-scale',None,None),
                  ('full-output-6000x4000',(6000,4000),(0,0)),
                  ('libraw-visible-6024x4024-centered',(6024,4024),(12,12)),
                  ('storage-6048x4024-centered',(6048,4024),(24,12))]
    fits = []
    def stats(errors):
        lengths = np.linalg.norm(errors,axis=1)
        return {'count':len(lengths),'rms':float(np.sqrt(np.mean(lengths**2))),
                'median':float(np.median(lengths)),'p95':float(np.percentile(lengths,95)),'maximum':float(lengths.max())}
    for name, size, origin in candidates:
        def predict(params, coords):
            zoom,tx,ty = params
            p = center + (coords-center)*zoom
            if size is not None:
                c = np.array(size)/2
                delta = p + origin - c
                r = np.linalg.norm(delta,axis=1) / np.linalg.norm(c)
                factor = np.interp(r*(n-1)-.5,np.arange(n),nodes)
                p = c + delta*factor[:,None] - origin
            return p + np.array([tx,ty])
        fit = least_squares(lambda p:(predict(p,q[train])-measured[train]).ravel(),[1,0,0],
                            bounds=([.9,-100,-100],[1.1,100,100]),ftol=1e-12,xtol=1e-12,gtol=1e-10)
        fits.append({'candidate':name,'nuisanceFit':'Isotropic output zoom and x/y translation on checkerboard training patches only; coefficients not distributed or used by product',
                     'optimizerSuccess':bool(fit.success),'trainingResidualOriginalPixels':stats(predict(fit.x,q[train])-measured[train]),
                     'holdoutResidualOriginalPixels':stats(predict(fit.x,q[validate])-measured[validate])})
    d = np.linalg.norm(measured-q,axis=1)
    normalized_radius = np.linalg.norm(q-center,axis=1)/np.linalg.norm(center)
    quadrants = [int(np.sum(((q[:,0]>=3000).astype(int)+2*(q[:,1]>=2000).astype(int))==i)) for i in range(4)]
    report = {'scope':'One public A6000 scene, Lightroom profile-off vs Adobe D100/V0 exports, both with mandatory builtin CA. Spatial agreement observation, not manufacturer frame selection, optical truth, TCA/vignette acceptance or product support.',
              'sourceRAW':{'fixture':fixture['file'],'sha256':fixture['sha256']},'exports':exports,
              'builtinCA':{'evidence':'Lightroom builtin profile information popup observed during acquisition',
                           'camera':'Sony ILCE-6000','lens':'E 18-55mm F3.5-5.6 OSS',
                           'automaticallyApplied':True,'components':['chromatic-aberration'],
                           'baselineFullyUncorrected':False},
              'registration':{'observationScale':scale,'pixelInput':'8-bit reduced luminance from original 16-bit sRGB PNG; spatial comparison only',
                              'patchPixels':2*radius+1,'searchRadiusPixels':search_radius,'minimumNCC':.97,'minimumPeakMargin':.015,
                              'refinement':'Independent cubic local affine patch alignment, normalized intensities, minimum refined NCC .985',
                              'acceptedPatches':len(accepted),'trainCount':int(sum(train)),'holdoutCount':int(sum(validate)),
                              'acceptedPerQuadrant':quadrants,'acceptedRadiusRangeHalfDiagonal':[float(normalized_radius.min()),float(normalized_radius.max())],
                              'sourceMinusOutputDistanceOriginalPixels':{'median':float(np.median(d)),'maximum':float(d.max())},
                              'controls':controls,'observations':points},'candidateFits':fits,
              'manufacturerFrameProven':False,'automaticRouteEnabled':False,
              'limitations':['Adobe uses its own optical calibration, not necessarily the Sony embedded table.',
                             'A best fitting frame is not a manufacturer contract and must not enable product rendering.',
                             'One natural scene and local patch translation have finite accuracy; no all-camera coverage claim.',
                             'Vignetting was set to zero; ordinary AutoLateralCA=0 does not disable builtin CA.'],
              'environment':{'macOS':platform.mac_ver()[0],'numpy':np.__version__,'scipy':scipy.__version__,'Pillow':pillow_version},
              'scriptSHA256':digest(Path(__file__)),'failures':failures}
    out = WORK/f'lightroom-sony-geometry-observation-{scale:g}.json'
    out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'report':str(out.relative_to(ROOT)),'accepted':len(accepted),'controls':controls,'candidateFits':fits},ensure_ascii=False,indent=2))


if __name__ == '__main__':
    main()
