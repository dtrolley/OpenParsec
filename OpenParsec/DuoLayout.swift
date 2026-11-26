import UIKit

// MARK: - Laptop layout for iPhone Duo
//
// When an iPhone Duo is half-folded like a laptop, the stream moves to the top half and the
// bottom half becomes a Mac-style keyboard above a trackpad. The fold position comes from the
// system's division reserved region; the posture comes from UIHingeInteraction (iOS 27.1).
// "On" forces the layout on any iPhone, which is also how it is exercised in the Simulator.

enum DuoLayoutMode: Int, CaseIterable {
	case auto
	case on
	case off

	var label: String {
		switch self {
		case .auto: return "Auto"
		case .on: return "On"
		case .off: return "Off"
		}
	}

	var next: DuoLayoutMode {
		let all = DuoLayoutMode.allCases
		return all[(all.firstIndex(of: self)! + 1) % all.count]
	}
}

/// Where the stream and the deck go, in the controller view's coordinates.
struct DuoLayoutFrames {
	var stream: CGRect
	var deck: CGRect?
}

enum DuoLayoutGeometry {
	/// Splits `bounds` at the fold when there is a horizontal one; otherwise at a fixed share.
	static func frames(bounds: CGRect, fold: CGRect?, active: Bool) -> DuoLayoutFrames {
		guard active, bounds.width > 0, bounds.height > 0 else {
			return DuoLayoutFrames(stream: bounds, deck: nil)
		}
		if let fold = fold, fold.width > fold.height, fold.minY > bounds.minY, fold.maxY < bounds.maxY {
			let stream = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: fold.minY - bounds.minY)
			let deck = CGRect(x: bounds.minX, y: fold.maxY, width: bounds.width, height: bounds.maxY - fold.maxY)
			return DuoLayoutFrames(stream: stream, deck: deck)
		}
		// No usable fold (a normal iPhone, or a sideways fold): portrait splits in half; landscape
		// keeps more room for the picture.
		let share: CGFloat = bounds.height > bounds.width ? 0.5 : 0.58
		let streamHeight = (bounds.height * share).rounded()
		return DuoLayoutFrames(
			stream: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: streamHeight),
			deck: CGRect(x: bounds.minX, y: bounds.minY + streamHeight, width: bounds.width, height: bounds.height - streamHeight))
	}
}

// MARK: - Deck (keyboard above trackpad)

final class DuoDeckView: UIView {
	let keyboard = DuoKeyboardView()
	let trackpad: TouchOverlayView

	init(trackpadDelegate: ParsecTouchInputDelegate) {
		trackpad = TouchOverlayView(frame: .zero)
		super.init(frame: .zero)
		backgroundColor = UIColor(white: 0.11, alpha: 1)
		isMultipleTouchEnabled = true

		trackpad.isTrackpad = true
		trackpad.inputDelegate = trackpadDelegate
		trackpad.isMultipleTouchEnabled = true
		trackpad.backgroundColor = UIColor(white: 0.2, alpha: 1)
		trackpad.layer.cornerRadius = 14
		trackpad.layer.cornerCurve = .continuous
		trackpad.layer.borderWidth = 1
		trackpad.layer.borderColor = UIColor(white: 0.3, alpha: 1).cgColor

		addSubview(keyboard)
		addSubview(trackpad)
	}

	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	override func layoutSubviews() {
		super.layoutSubviews()
		let inset = UIEdgeInsets(top: 8, left: max(6, safeAreaInsets.left), bottom: max(8, safeAreaInsets.bottom), right: max(6, safeAreaInsets.right))
		let area = bounds.inset(by: inset)
		guard area.width > 0, area.height > 0 else { return }
		let gap: CGFloat = 10
		// Keys need height to be hittable; the trackpad gets the rest, but never less than a third.
		let keyboardHeight = min(area.height * 0.64, area.width * 0.52)
		keyboard.frame = CGRect(x: area.minX, y: area.minY, width: area.width, height: keyboardHeight)
		let padTop = keyboard.frame.maxY + gap
		let padWidth = area.width * 0.72
		trackpad.frame = CGRect(x: area.midX - padWidth / 2, y: padTop, width: padWidth, height: max(0, area.maxY - padTop))
	}

	func releaseAll() {
		keyboard.releaseAll()
	}
}

// MARK: - Keyboard

/// A Mac-layout keyboard that sends HID usages straight to the host: a real key-down on touch and
/// key-up on lift, so holds, chords and the host's own shortcuts all work.
final class DuoKeyboardView: UIView {
	struct Key {
		let label: String
		let shifted: String?
		let code: UInt32
		let width: CGFloat       // relative to a letter key
		var isModifier: Bool { DuoKeyboardView.modifierCodes.contains(code) }
	}

	// HID usages for modifiers (Parsec keycodes are HID usages).
	static let modifierCodes: Set<UInt32> = [224, 225, 226, 227, 228, 229, 230, 231]

	private static func k(_ label: String, _ code: UInt32, _ width: CGFloat = 1, shifted: String? = nil) -> Key {
		Key(label: label, shifted: shifted, code: code, width: width)
	}

	private static func letters(_ s: String, _ codes: [UInt32]) -> [Key] {
		zip(s, codes).map { k(String($0.0), $0.1, shifted: String($0.0).uppercased()) }
	}

	private let rows: [[Key]] = {
		let fn: [Key] = [k("esc", 41, 1.3)] + (1...12).map { k("F\($0)", UInt32(57 + $0)) } + [k("del", 76, 1.3)]
		let num: [Key] = [k("`", 53, shifted: "~"), k("1", 30, shifted: "!"), k("2", 31, shifted: "@"), k("3", 32, shifted: "#"),
						  k("4", 33, shifted: "$"), k("5", 34, shifted: "%"), k("6", 35, shifted: "^"), k("7", 36, shifted: "&"),
						  k("8", 37, shifted: "*"), k("9", 38, shifted: "("), k("0", 39, shifted: ")"), k("-", 45, shifted: "_"),
						  k("=", 46, shifted: "+"), k("⌫", 42, 1.5)]
		let top: [Key] = [k("⇥", 43, 1.5)] + letters("qwertyuiop", [20, 26, 8, 21, 23, 28, 24, 12, 18, 19])
			+ [k("[", 47, shifted: "{"), k("]", 48, shifted: "}"), k("\\", 49, shifted: "|")]
		let home: [Key] = [k("⇪", 57, 1.8)] + letters("asdfghjkl", [4, 22, 7, 9, 10, 11, 13, 14, 15])
			+ [k(";", 51, shifted: ":"), k("'", 52, shifted: "\""), k("return", 40, 1.8)]
		let bottom: [Key] = [k("⇧", 225, 2.3)] + letters("zxcvbnm", [29, 27, 6, 25, 5, 17, 16])
			+ [k(",", 54, shifted: "<"), k(".", 55, shifted: ">"), k("/", 56, shifted: "?"), k("⇧", 229, 2.3)]
		let space: [Key] = [k("ctrl", 224, 1.2), k("opt", 226, 1.2), k("cmd", 227, 1.5), k("", 44, 5.2),
							k("cmd", 231, 1.5), k("opt", 230, 1.2), k("←", 80), k("↑", 82), k("↓", 81), k("→", 79)]
		return [fn, num, top, home, bottom, space]
	}()

	private enum ModState { case off, held(used: Bool), latched, locked }

	private var keyViews: [[UILabel]] = []
	private var touchKeys: [UITouch: (row: Int, col: Int)] = [:]
	private var modStates: [UInt32: ModState] = [:]
	private var repeatTimer: Timer?
	private let haptic = UIImpactFeedbackGenerator(style: .light)

	override init(frame: CGRect) {
		super.init(frame: frame)
		isMultipleTouchEnabled = true
		for row in rows {
			keyViews.append(row.map { key in
				let label = UILabel()
				label.text = key.label
				label.textAlignment = .center
				label.textColor = .white
				label.adjustsFontSizeToFitWidth = true
				label.minimumScaleFactor = 0.5
				label.backgroundColor = UIColor(white: 0.24, alpha: 1)
				label.layer.cornerRadius = 5
				label.layer.cornerCurve = .continuous
				label.clipsToBounds = true
				label.isUserInteractionEnabled = false
				addSubview(label)
				return label
			})
		}
	}

	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	override func layoutSubviews() {
		super.layoutSubviews()
		let gap: CGFloat = 4
		// The function row is shorter, as on a Mac.
		let weights: [CGFloat] = rows.indices.map { $0 == 0 ? 0.7 : 1 }
		let unitHeight = (bounds.height - gap * CGFloat(rows.count - 1)) / weights.reduce(0, +)
		var y: CGFloat = 0
		for (r, row) in rows.enumerated() {
			let h = unitHeight * weights[r]
			let totalWidth = row.reduce(0) { $0 + $1.width }
			let unit = (bounds.width - gap * CGFloat(row.count - 1)) / totalWidth
			var x: CGFloat = 0
			for (c, key) in row.enumerated() {
				let w = unit * key.width
				keyViews[r][c].frame = CGRect(x: x, y: y, width: w, height: h).integral
				keyViews[r][c].font = .systemFont(ofSize: min(18, h * (key.label.count > 1 ? 0.34 : 0.48)), weight: .regular)
				x += w + gap
			}
			y += h + gap
		}
	}

	// Slightly forgiving hit test: the nearest key in the touched row, so the gaps never swallow a tap.
	private func keyIndex(at p: CGPoint) -> (row: Int, col: Int)? {
		guard let r = keyViews.firstIndex(where: { row in
			guard let f = row.first?.frame else { return false }
			return p.y <= f.maxY + 2
		}) else { return nil }
		let row = keyViews[r]
		guard let c = row.indices.min(by: { abs(row[$0].frame.midX - p.x) < abs(row[$1].frame.midX - p.x) }) else { return nil }
		return (r, c)
	}

	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
		for t in touches {
			guard let idx = keyIndex(at: t.location(in: self)) else { continue }
			touchKeys[t] = idx
			keyDown(rows[idx.row][idx.col])
			keyViews[idx.row][idx.col].backgroundColor = UIColor(white: 0.5, alpha: 1)
			haptic.impactOccurred()
		}
	}

	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }
	override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }

	private func lift(_ touches: Set<UITouch>) {
		for t in touches {
			guard let idx = touchKeys.removeValue(forKey: t) else { continue }
			keyUp(rows[idx.row][idx.col])
			refreshKey(row: idx.row, col: idx.col)
		}
	}

	// Modifiers: hold for a chord, tap to latch for the next key, tap again to lock, tap a lock to clear.
	private func keyDown(_ key: Key) {
		if key.isModifier {
			switch modStates[key.code] ?? .off {
			case .off:
				CParsec.sendKeyboardMessage(keyCode: key.code, pressed: true)
				modStates[key.code] = .held(used: false)
			case .latched:
				modStates[key.code] = .locked
			case .locked:
				CParsec.sendKeyboardMessage(keyCode: key.code, pressed: false)
				modStates[key.code] = .off
			case .held:
				break
			}
			refreshAll()
			return
		}
		for (code, state) in modStates {
			if case .held = state { modStates[code] = .held(used: true) }
		}
		CParsec.sendKeyboardMessage(keyCode: key.code, pressed: true)
		startRepeat(key.code)
	}

	private func keyUp(_ key: Key) {
		if key.isModifier {
			if case .held(let used) = modStates[key.code] ?? .off {
				if used {
					CParsec.sendKeyboardMessage(keyCode: key.code, pressed: false)
					modStates[key.code] = .off
				} else {
					modStates[key.code] = .latched
				}
			}
			refreshAll()
			return
		}
		stopRepeat()
		CParsec.sendKeyboardMessage(keyCode: key.code, pressed: false)
		// A latched modifier applies to one key only.
		for (code, state) in modStates {
			if case .latched = state {
				CParsec.sendKeyboardMessage(keyCode: code, pressed: false)
				modStates[code] = .off
			}
		}
		refreshAll()
	}

	// Parsec input does not auto-repeat on the host, so repeat held keys here (same timing as
	// ParsecViewController's hardware-keyboard repeat).
	private func startRepeat(_ code: UInt32) {
		stopRepeat()
		guard code != 57 else { return }   // never repeat caps lock
		repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
			self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { _ in
				CParsec.sendKeyboardMessage(keyCode: code, pressed: false)
				CParsec.sendKeyboardMessage(keyCode: code, pressed: true)
			}
		}
	}

	private func stopRepeat() {
		repeatTimer?.invalidate()
		repeatTimer = nil
	}

	/// Lifts every key and modifier this keyboard has down on the host.
	func releaseAll() {
		stopRepeat()
		for (_, idx) in touchKeys {
			let key = rows[idx.row][idx.col]
			if !key.isModifier { CParsec.sendKeyboardMessage(keyCode: key.code, pressed: false) }
		}
		touchKeys.removeAll()
		for (code, state) in modStates {
			if case .off = state { continue }
			CParsec.sendKeyboardMessage(keyCode: code, pressed: false)
		}
		modStates.removeAll()
		refreshAll()
	}

	private var shiftActive: Bool {
		[225, 229].contains { code in
			if case .off = modStates[UInt32(code)] ?? .off { return false }
			return true
		}
	}

	private func refreshAll() {
		for r in rows.indices {
			for c in rows[r].indices { refreshKey(row: r, col: c) }
		}
	}

	private func refreshKey(row r: Int, col c: Int) {
		let key = rows[r][c]
		let label = keyViews[r][c]
		label.text = shiftActive ? (key.shifted ?? key.label) : key.label
		let pressed = touchKeys.values.contains { $0.row == r && $0.col == c }
		var color = UIColor(white: pressed ? 0.5 : 0.24, alpha: 1)
		if key.isModifier {
			switch modStates[key.code] ?? .off {
			case .off: break
			case .held, .latched: color = UIColor(white: 0.55, alpha: 1)
			case .locked: color = .systemBlue
			}
		}
		label.backgroundColor = color
	}
}

// MARK: - Controller wiring

/// Lets the stream's tap / long-press recognizers see only touches on the picture or trackpad, so
/// typing on the deck keyboard never clicks on the host.
final class OverlayOnlyGestureFilter: NSObject, UIGestureRecognizerDelegate {
	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
		return touch.view is TouchOverlayView
	}
}

extension ParsecViewController {
	func installHingeObserver() {
		// The hinge API ships in the iOS 27.1 SDK; older toolchains (upstream CI) build without it
		// and get the manual "On" mode only.
		#if compiler(>=6.4)
		if #available(iOS 27.1, *) {
			let interaction = UIHingeInteraction { [weak self] _, update in
				guard let self else { return }
				let partiallyOpen = update.hinge?.status == .partiallyOpen
				if partiallyOpen != self.hingePartiallyOpen {
					self.hingePartiallyOpen = partiallyOpen
					self.view.setNeedsLayout()
				}
			}
			view.addInteraction(interaction)
		}
		#endif
	}

	func setLayoutMode(_ mode: DuoLayoutMode) {
		layoutMode = mode
		SettingsHandler.duoLayout = mode
		view.setNeedsLayout()
	}

	/// The active fold, in the controller view's coordinates, if the device reports one.
	private var foldFrame: CGRect? {
		#if compiler(>=6.4)
		if #available(iOS 27.1, *) {
			return view.reservedRegions(kind: .division).first(where: { $0.isActive })?.frame
		}
		#endif
		return nil
	}

	/// Puts the stream above the fold and the deck below it, or the stream full screen. Called from
	/// viewDidLayoutSubviews before the stream is sized to streamView.
	func applyLaptopLayout() {
		let fold = foldFrame
		// Auto wants the laptop posture: half-open with the fold running across the screen. A
		// half-open book posture (fold top-to-bottom) keeps the full-screen stream.
		let foldAcross = fold.map { $0.width > $0.height } ?? true
		let active = layoutMode == .on || (layoutMode == .auto && hingePartiallyOpen && foldAcross)
		let frames = DuoLayoutGeometry.frames(bounds: view.bounds, fold: fold, active: active)
		if let deckFrame = frames.deck {
			if deckView == nil {
				let deck = DuoDeckView(trackpadDelegate: self)
				view.insertSubview(deck, aboveSubview: streamView)
				deckView = deck
				// The deck has its own keyboard; drop the system one if it was up.
				if keyboardVisible {
					setKeyboardVisible(false)
					onKeyboardVisibilityChanged?(false)
				}
			}
			deckView?.frame = deckFrame
		} else if let deck = deckView {
			deck.releaseAll()
			deck.removeFromSuperview()
			deckView = nil
			cursorTouchFromTrackpad = false
		}
		if streamView.frame != frames.stream {
			if scrollView.zoomScale != 1.0 { scrollView.zoomScale = 1.0 }
			streamView.frame = frames.stream
		}
	}

	func isTrackpadGesture(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		guard let pad = deckView?.trackpad else { return false }
		return pad.bounds.contains(gestureRecognizer.location(in: pad))
	}
}
