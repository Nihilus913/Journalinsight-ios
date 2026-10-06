import Foundation

/// W-FIX-P3 RG-87: VoiceOver reads an unlabeled SF Symbol by Apple's own name for it ("heart" →
/// "Love", "moon" → "Do Not Disturb", "sun.max" → "brightness higher", "waveform.path.ecg" →
/// "Ecg Waveform Path"). An icon beside a title therefore carries the title it stands for.
public nonisolated func jiSymbolAccessibilityLabel(_ systemName: String, title: String) -> String { title }
