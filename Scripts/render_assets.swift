import AppKit
let root = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
let fm=FileManager.default
try fm.createDirectory(at:root,withIntermediateDirectories:true)
func png(_ size:NSSize, scale:CGFloat = 1, _ draw:()->Void)->Data {
 let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size.width*scale),pixelsHigh:Int(size.height*scale),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 bitmap.size=size
 NSGraphicsContext.saveGraphicsState()
 let context=NSGraphicsContext(bitmapImageRep:bitmap)!;NSGraphicsContext.current=context
 context.cgContext.scaleBy(x:scale,y:scale);draw()
 NSGraphicsContext.restoreGraphicsState()
 return bitmap.representation(using:.png,properties:[:])!
}
func text(_ string:String,_ x:CGFloat,_ y:CGFloat,_ font:NSFont,_ color:NSColor) {
 (string as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:[.font:font,.foregroundColor:color])
}
func logo(_ rect:NSRect) {
 let base=NSBezierPath(roundedRect:rect,xRadius:rect.width*0.225,yRadius:rect.height*0.225)
 NSGradient(colors:[NSColor(calibratedRed:0.08,green:0.39,blue:0.92,alpha:1),NSColor(calibratedRed:0.02,green:0.66,blue:0.85,alpha:1)])!.draw(in:base,angle:35)
 let center=NSPoint(x:rect.midX,y:rect.midY), radius=rect.width*0.31
 let ring=NSBezierPath(ovalIn:NSRect(x:center.x-radius,y:center.y-radius,width:radius*2,height:radius*2));ring.lineWidth=rect.width*0.028;NSColor.white.withAlphaComponent(0.85).setStroke();ring.stroke()
 for i in 0..<6 {
  let a=CGFloat(i)*CGFloat.pi/3, b=a+CGFloat.pi*0.48
  let p=NSBezierPath();p.move(to:NSPoint(x:center.x+cos(a)*radius*0.77,y:center.y+sin(a)*radius*0.77));p.line(to:NSPoint(x:center.x+cos(b)*radius*0.33,y:center.y+sin(b)*radius*0.33));p.lineWidth=rect.width*0.034;NSColor.white.withAlphaComponent(0.9).setStroke();p.stroke()
 }
}
let icons=root.appendingPathComponent("LensDock.iconset",isDirectory:true);try fm.createDirectory(at:icons,withIntermediateDirectories:true)
for size in [16,32,128,256,512] {
 for factor in [1,2] {
  let pixels=size*factor
  let data=png(NSSize(width:CGFloat(pixels),height:CGFloat(pixels))){logo(NSRect(x:CGFloat(pixels)*0.045,y:CGFloat(pixels)*0.045,width:CGFloat(pixels)*0.91,height:CGFloat(pixels)*0.91))}
  try data.write(to:icons.appendingPathComponent("icon_\(size)x\(size)\(factor==2 ? "@2x" : "").png"))
 }
}
// Finder content is 760 x 480 points. All artwork is original vector geometry.
func drawBackground() {
 NSGradient(colors:[NSColor(calibratedWhite:0.99,alpha:1),NSColor(calibratedRed:0.93,green:0.96,blue:1,alpha:1)])!.draw(in:NSRect(x:0,y:0,width:760,height:480),angle:-40)
 for (i,radius) in [CGFloat(225),CGFloat(190),CGFloat(156)].enumerated(){let ring=NSBezierPath(ovalIn:NSRect(x:565-radius,y:375-radius,width:radius*2,height:radius*2));ring.lineWidth=1.2;NSColor(calibratedRed:0.21,green:0.55,blue:0.91,alpha:CGFloat(i+1)*0.025).setStroke();ring.stroke()}
 text("LensDock",46,388,.systemFont(ofSize:34,weight:.semibold),NSColor(calibratedWhite:0.13,alpha:1))
 text("镜头坞 · 保留 RAW 的镜头矫正",48,363,.systemFont(ofSize:14),NSColor(calibratedWhite:0.4,alpha:1))
 let badge=NSBezierPath(roundedRect:NSRect(x:627,y:395,width:85,height:25),xRadius:12,yRadius:12);NSColor(calibratedRed:0.17,green:0.44,blue:0.8,alpha:0.09).setFill();badge.fill()
 text("预览版 0.1",639,402,.systemFont(ofSize:11,weight:.medium),NSColor(calibratedRed:0.16,green:0.37,blue:0.65,alpha:1))
 for x in [CGFloat(153),CGFloat(507)] {let tile=NSBezierPath(roundedRect:NSRect(x:x,y:180,width:100,height:106),xRadius:24,yRadius:24);NSColor.white.withAlphaComponent(0.8).setFill();tile.fill()}
 let arrow=NSBezierPath();arrow.move(to:NSPoint(x:318,y:237));arrow.line(to:NSPoint(x:432,y:237));arrow.move(to:NSPoint(x:420,y:249));arrow.line(to:NSPoint(x:432,y:237));arrow.line(to:NSPoint(x:420,y:225));arrow.lineWidth=2.2;NSColor(calibratedRed:0.3,green:0.51,blue:0.76,alpha:0.65).setStroke();arrow.stroke()
 text("拖入“应用程序”",326,203,.systemFont(ofSize:12,weight:.medium),NSColor(calibratedWhite:0.4,alpha:1))
 let line=NSBezierPath();line.move(to:NSPoint(x:46,y:122));line.line(to:NSPoint(x:714,y:122));line.lineWidth=1;NSColor(calibratedWhite:0.75,alpha:0.25).setStroke();line.stroke()
 text("说明与源码",48,94,.systemFont(ofSize:11,weight:.medium),NSColor(calibratedWhite:0.52,alpha:1))
 text("需要兼容的本机 Pixelmator · Apple 芯片 Mac",48,23,.systemFont(ofSize:11),NSColor(calibratedWhite:0.48,alpha:1))
}
try png(NSSize(width:760,height:480),drawBackground).write(to:root.appendingPathComponent("DMG-background.png"))
try png(NSSize(width:760,height:480),scale:2,drawBackground).write(to:root.appendingPathComponent("DMG-background@2x.png"))

var media=CGRect(x:0,y:0,width:760,height:480)
let consumer=CGDataConsumer(url:root.appendingPathComponent("DMG-background.pdf") as CFURL)!
let pdf=CGContext(consumer:consumer,mediaBox:&media,nil)!
pdf.beginPDFPage(nil)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current=NSGraphicsContext(cgContext:pdf,flipped:false)
drawBackground()
NSGraphicsContext.restoreGraphicsState()
pdf.endPDFPage();pdf.closePDF()
