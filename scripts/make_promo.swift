// scripts/screenshots.sh'in aldığı ham ekran görüntülerini README görsellerine ve sosyal medya story'lerine
// dönüştürür. PhoneDrop'un tools/make_promo.swift'iyle aynı görsel dil (sarı zemin, yuvarlak yazı, gölgeli pencere).
//   swift scripts/make_promo.swift <ham-klasör> <readme-çıktı> <story-çıktı>
import AppKit

let args = CommandLine.arguments
guard args.count == 4 else { fatalError("kullanım: make_promo.swift <ham-klasör> <readme-çıktı> <story-çıktı>") }
let (shots, readmeOut, storiesOut) = (args[1], args[2], args[3])
for dir in [readmeOut, storiesOut] { try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true) }

func load(_ name: String) -> CGImage {
    let url = URL(fileURLWithPath: "\(shots)/\(name).png")
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("eksik: \(url.path)") }
    return img
}

func rgb(_ hex: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}

let ink = rgb(0x2B2A28), cream = rgb(0xFFFBF0)

/// Sol üst köşe başlangıçlı bir bitmap.
final class Canvas {
    let w: CGFloat, h: CGFloat
    let ctx: CGContext

    init(_ w: Int, _ h: Int) {
        self.w = CGFloat(w); self.h = CGFloat(h)
        ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
    }

    func image(_ img: CGImage, in r: CGRect) {
        ctx.saveGState()
        ctx.translateBy(x: r.minX, y: r.maxY); ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(origin: .zero, size: r.size))
        ctx.restoreGState()
    }

    func background(_ top: NSColor, _ bottom: NSColor) {
        let g = CGGradient(colorsSpace: nil, colors: [top.cgColor, bottom.cgColor] as CFArray, locations: nil)!
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: w * 0.35, y: h),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    /// Büyük düz alanlar boş görünmesin diye yumuşak bir ışık lekesi.
    func glow(x: CGFloat, y: CGFloat, radius: CGFloat, _ color: NSColor) {
        let g = CGGradient(colorsSpace: nil, colors: [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray, locations: nil)!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: radius, options: [])
    }

    func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil) }

    func fill(_ path: CGPath, _ color: NSColor, shadow: CGFloat = 0) {
        ctx.saveGState()
        if shadow > 0 { ctx.setShadow(offset: CGSize(width: 0, height: -shadow * 0.4), blur: shadow, color: NSColor.black.withAlphaComponent(0.28).cgColor) }
        ctx.addPath(path); ctx.setFillColor(color.cgColor); ctx.fillPath()
        ctx.restoreGState()
    }

    func stroke(_ path: CGPath, _ color: NSColor, _ width: CGFloat) {
        ctx.addPath(path); ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(width); ctx.strokePath()
    }

    /// Satır kaydırarak yazar, yüksekliği döndürür.
    @discardableResult
    func text(_ s: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular,
              color: NSColor = ink, align: NSTextAlignment = .left, spacing: CGFloat = 0, kern: CGFloat = 0) -> CGFloat {
        let p = NSMutableParagraphStyle(); p.alignment = align; p.lineSpacing = spacing
        // Uygulama yuvarlak sistem yazısını kullanıyor; görseller de öyle.
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p, .kern: kern])
        let box = str.boundingRect(with: CGSize(width: width, height: 10_000), options: [.usesLineFragmentOrigin])
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        str.draw(with: CGRect(x: x, y: y, width: width, height: ceil(box.height)), options: [.usesLineFragmentOrigin])
        NSGraphicsContext.restoreGraphicsState()
        return ceil(box.height)
    }

    /// Yuvarlak köşeli, gölgeli ekran görüntüsü (pencere ya da menü çubuğu penceresi). Çerçevesini döndürür.
    @discardableResult
    func shot(_ name: String, x: CGFloat, y: CGFloat, width: CGFloat, radius: CGFloat? = nil) -> CGRect {
        let img = load(name)
        let r = CGRect(x: x, y: y, width: width, height: Canvas.height(name, width: width))
        // Pencere ~11 pt / 1100 pt, menü penceresi ~12 pt / 300 pt köşe yarıçapı.
        let path = rounded(r, radius ?? width * (img.width < 1500 ? 0.04 : 0.011))
        fill(path, .black, shadow: max(30, width * 0.05))
        ctx.saveGState(); ctx.addPath(path); ctx.clip(); image(img, in: r); ctx.restoreGState()
        stroke(path, NSColor.black.withAlphaComponent(0.12), 1.5)
        return r
    }

    static func height(_ name: String, width: CGFloat) -> CGFloat {
        let img = load(name)
        return width * CGFloat(img.height) / CGFloat(img.width)
    }

    func save(_ path: String) {
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        print(path)
    }
}

func brand(_ c: Canvas) {
    c.background(rgb(0xFFE27A), rgb(0xFFCB2E))
    c.glow(x: c.w * 0.85, y: c.h * 0.12, radius: c.w * 0.7, NSColor.white.withAlphaComponent(0.45))
    c.glow(x: c.w * 0.05, y: c.h * 0.95, radius: c.w * 0.8, rgb(0xFFB800, 0.5))
}

struct Texts {
    let lang: String
    let captions: [String: String]
    let stories: [(title: String, body: String)]
    let footer: String
}

let all = [
    Texts(lang: "en", captions: [
        "overview": "Overview", "cleanup": "Smart Cleanup", "cleaned": "After a cleanup", "largefiles": "Large & old files",
        "leftovers": "App leftovers", "launchitems": "Launch items", "settings": "Settings, light theme", "menu": "Menu bar",
    ], stories: [
        ("Freshen up\nyour Mac", "Caches, logs, browser data and developer leftovers, on one screen."),
        ("See it first.\nThen clean.", "Scan to see how much space each category frees up. Only the tasks you tick are cleaned."),
        ("Find large and\nold files", "Videos, disk images and archives you haven't opened in a while. They go to the Trash, so you can get them back."),
        ("Leftovers of\napps you\nremoved", "Finds caches and support files left in ~/Library, and the launch items that start in the background."),
        ("One click,\nfrom the menu bar", "Menu bar, desktop widget and scheduled cleanup. Free and open source, English and Turkish."),
    ], footer: "github.com/osbendes/freshmymac"),
    Texts(lang: "tr", captions: [
        "overview": "Genel bakış", "cleanup": "Akıllı Temizlik", "cleaned": "Temizlikten sonra", "largefiles": "Büyük ve eski dosyalar",
        "leftovers": "Uygulama kalıntıları", "launchitems": "Açılış öğeleri", "settings": "Ayarlar, açık tema", "menu": "Menü çubuğu",
    ], stories: [
        ("Mac'ini\ntazele", "Önbellekler, günlükler, tarayıcı verileri ve geliştirici artıkları tek ekranda."),
        ("Önce gör.\nSonra temizle.", "Tara, her kategoride ne kadar yer açılacağını gör. Yalnızca işaretlediğin görevler temizlenir."),
        ("Büyük ve eski\ndosyaları bul", "Uzun süredir açmadığın videolar, disk görüntüleri, arşivler. Çöp Kutusu'na taşınır, geri alabilirsin."),
        ("Kaldırdığın\nuygulamaların\nartıkları", "~/Library'de kalan önbellek ve destek dosyalarını, arka planda başlayan açılış öğelerini bulur."),
        ("Tek tık,\nmenü çubuğundan", "Menü çubuğu, masaüstü widget'ı ve zamanlanmış temizlik. Ücretsiz ve açık kaynak, Türkçe ve İngilizce."),
    ], footer: "github.com/osbendes/freshmymac"),
]

for t in all {
    let l = t.lang

    // README: büyük pencere, yanında menü çubuğu penceresi
    do {
        let c = Canvas(2000, 1180)
        brand(c)
        let mh = c.h - 150
        let mw = mh * 1000 / Canvas.height("overview-\(l)-dark", width: 1000)
        let menuW: CGFloat = 430, overlap: CGFloat = 190
        let left = (c.w - mw - menuW + overlap) / 2
        c.shot("overview-\(l)-dark", x: left, y: 75, width: mw)
        let menuH = Canvas.height("menu-\(l)-light", width: menuW)
        c.shot("menu-\(l)-light", x: left + mw - overlap, y: c.h - 75 - menuH, width: menuW)
        c.save("\(readmeOut)/hero-\(l).png")
    }

    // README: ekranlar (2 satır × 4)
    do {
        let rows = [["overview-\(l)-dark", "cleanup-\(l)-dark", "cleaned-\(l)-dark", "largefiles-\(l)-dark"],
                    ["leftovers-\(l)-light", "launchitems-\(l)-light", "settings-\(l)-light", "menu-\(l)-light"]]
        let w: CGFloat = 440, gap: CGFloat = 50, top: CGFloat = 70, captionH: CGFloat = 110
        let cell = Canvas.height("overview-\(l)-dark", width: w)
        let c = Canvas(Int(gap + 4 * (w + gap)), Int(top + 2 * (cell + captionH)))
        c.background(cream, rgb(0xFFF4C7))
        for (r, row) in rows.enumerated() {
            let y = top + CGFloat(r) * (cell + captionH)
            for (i, name) in row.enumerated() {
                let x = gap + CGFloat(i) * (w + gap)
                if name.hasPrefix("menu") {
                    // Menü penceresi hücreye sığacak kadar küçültülür, ortalanır.
                    let mw = min(w, cell * 1000 / Canvas.height(name, width: 1000))
                    c.shot(name, x: x + (w - mw) / 2, y: y + (cell - Canvas.height(name, width: mw)) / 2, width: mw)
                } else {
                    c.shot(name, x: x, y: y, width: w)
                }
                let key = String(name.prefix { $0 != "-" })
                c.text(t.captions[key]!, x: x, y: y + cell + 30, width: w, size: 26, weight: .medium, align: .center)
            }
        }
        c.save("\(readmeOut)/screens-\(l).png")
    }

    // Story'ler (1080x1920). Üst ve alttaki ~250 px yazısız kalır: uygulamalar orada kendi arayüzünü çizer.
    for (i, s) in t.stories.enumerated() {
        let c = Canvas(1080, 1920)
        brand(c)
        c.text("FRESHMYMAC", x: 90, y: 270, width: 900, size: 30, weight: .bold, color: ink.withAlphaComponent(0.6), kern: 6)
        var y: CGFloat = 325
        y += c.text(s.title, x: 90, y: y, width: 900, size: 92, weight: .heavy, spacing: -6) + 28
        y += c.text(s.body, x: 90, y: y, width: 880, size: 38, weight: .medium, color: ink.withAlphaComponent(0.85), spacing: 6) + 50
        let bottom: CGFloat = 1545
        let room = bottom - y

        /// Pencereyi, kalan alana sığacak en geniş boyutta ortalar.
        func window(_ name: String, most: CGFloat = 1000, x: CGFloat? = nil, top: CGFloat? = nil, height: CGFloat? = nil) {
            let h = height ?? room
            let width = min(most, h * 1000 / Canvas.height(name, width: 1000))
            c.shot(name, x: x ?? (1080 - width) / 2, y: top ?? (y + (h - Canvas.height(name, width: width)) / 2), width: width)
        }
        switch i {
        case 0:
            window("overview-\(l)-dark", most: 960, x: 40, height: room - 120)
            let mw: CGFloat = 380
            c.shot("menu-\(l)-light", x: 1080 - mw - 40, y: bottom - Canvas.height("menu-\(l)-light", width: mw), width: mw)
        case 1:
            window("cleanup-\(l)-light", most: 900, x: 40, top: y, height: room * 0.62)
            let w2: CGFloat = 900
            c.shot("cleaned-\(l)-dark", x: 1080 - w2 - 40, y: bottom - Canvas.height("cleaned-\(l)-dark", width: w2), width: w2)
        case 2:
            window("largefiles-\(l)-dark")
        case 3:
            window("leftovers-\(l)-light", most: 900, x: 40, top: y, height: room * 0.62)
            let w2: CGFloat = 900
            c.shot("launchitems-\(l)-dark", x: 1080 - w2 - 40, y: bottom - Canvas.height("launchitems-\(l)-dark", width: w2), width: w2)
        default:
            let mw = min(470, room * 1000 / Canvas.height("menu-\(l)-light", width: 1000))
            let mh = Canvas.height("menu-\(l)-light", width: mw)
            c.shot("menu-\(l)-light", x: 540 - mw - 20, y: y + (room - mh) / 2, width: mw)
            c.shot("menu-\(l)-dark", x: 540 + 20, y: y + (room - mh) / 2, width: mw)
        }
        let pill = CGRect(x: 220, y: 1590, width: 640, height: 76)
        c.fill(c.rounded(pill, 38), ink, shadow: 30)
        c.text(t.footer, x: pill.minX, y: pill.minY + 17, width: pill.width, size: 32, weight: .semibold, color: cream, align: .center)
        c.save("\(storiesOut)/story-\(l)-\(i + 1).png")
    }
}
