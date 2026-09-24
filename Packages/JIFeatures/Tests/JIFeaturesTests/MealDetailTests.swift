import Testing
import JICore
@testable import JIFeatures

struct MealDetailTests {
    @Test func sumsItemsAndKeepsMissingAsNil() {
        let d = mealDetail(slot: "lunch", items: [
            NutritionMealItem(name: "Rice box", amountG: 560, kcal: 526, proteinG: 48, carbsG: 58, fatG: nil),
            NutritionMealItem(name: "Whey", amountG: 30, kcal: 111, proteinG: 24, carbsG: 2, fatG: nil),
        ])
        #expect(d.title == "Lunch")
        #expect(d.kcal == 637)
        #expect(d.protein == 72)
        #expect(d.fat == nil)                 // no item had fat → "—", never 0
    }

    @Test func mealDetailHasNoWriteControl() {
        #expect(MealDetailSheet.actionTitles == ["Done"])
        #expect(nutritionReadOnlyNote.contains("never logs food"))
    }
}
