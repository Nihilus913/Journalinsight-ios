import JIDesign

/// B-57 §1 + v11 change 4: explainer copy shared by Energy (L3) and GateRationale (L2).
public nonisolated enum JIExplainers {
    public static let energyBalanceTitle = "How we calculate"
    public static let energyBalanceSteps: [HowWeCalculateStep] = [
        HowWeCalculateStep(title: "Burned = resting + active energy",
                           body: "Both read from Apple Health (Resting Energy and Active Energy). JI adds the two for each day and changes nothing."),
        HowWeCalculateStep(title: "Eaten = dietary energy in Apple Health",
                           body: "Written there by YAZIO. JI only reads the day total; it never logs food."),
        HowWeCalculateStep(title: "Balance = eaten − burned, 7-day average",
                           body: "Averaged over the last 7 complete days. Today counts once it ends. A day with no food in Health is skipped, not counted as zero."),
        HowWeCalculateStep(title: "Deficit or surplus",
                           body: "Inside your plan band reads On plan. Below the band: Deep deficit. Above it: Light deficit, and above 0: Surplus. The band comes from your weight goal in Goals."),
    ]
    public static let energyBalanceNote = "Watch and phone energy numbers are estimates. JI shows them as they are and makes no medical judgement from them."
    /// v11 change 2 + spec §2 L5: the nutrition source wording everywhere.
    public static let nutritionSourceLabel = "YAZIO via Apple Health"
}
