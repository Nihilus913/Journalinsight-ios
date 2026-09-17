import Foundation

/// W3a-L2 (P-nutrition). Mirrors the RN oracle's `NutritionMealItem`/`NutritionDayTotal`/
/// `NutritionDayBreakdown`/`NutritionDayDetail` (`mobile/src/data/types.ts`) field-for-field.
/// Every hub-nullable field stays `Optional` — CLAUDE.md rule 5 (never render a zero for
/// missing data): a `nil` here must reach the view as "no data", not `0`.
public struct NutritionMealItem: Codable, Sendable, Equatable {
    public var name: String
    public var amountG, kcal, proteinG, carbsG, fatG: Double?
    public init(name: String, amountG: Double? = nil, kcal: Double? = nil, proteinG: Double? = nil, carbsG: Double? = nil, fatG: Double? = nil) {
        self.name = name; self.amountG = amountG; self.kcal = kcal; self.proteinG = proteinG; self.carbsG = carbsG; self.fatG = fatG
    }
}

public struct NutritionDayTotal: Codable, Sendable, Equatable {
    public var kcal, kcalGoal, proteinG, carbsG, fatG: Double?
    public var mealsLogged: Int?
    public init(kcal: Double? = nil, kcalGoal: Double? = nil, proteinG: Double? = nil, carbsG: Double? = nil, fatG: Double? = nil, mealsLogged: Int? = nil) {
        self.kcal = kcal; self.kcalGoal = kcalGoal; self.proteinG = proteinG; self.carbsG = carbsG; self.fatG = fatG; self.mealsLogged = mealsLogged
    }
}

public struct NutritionDayBreakdown: Codable, Sendable, Equatable {
    public var breakfast, lunch, dinner, snack: Double?
    public init(breakfast: Double? = nil, lunch: Double? = nil, dinner: Double? = nil, snack: Double? = nil) {
        self.breakfast = breakfast; self.lunch = lunch; self.dinner = dinner; self.snack = snack
    }
}

/// The "meals" slice of the oracle's day-detail response — one meal-timeline day.
public struct NutritionDayDetail: Codable, Sendable, Equatable {
    public var date: String
    public var total: NutritionDayTotal
    public var breakdown: NutritionDayBreakdown
    /// Keyed by daytime: breakfast | lunch | dinner | snack | unknown — same shape as the oracle.
    public var items: [String: [NutritionMealItem]]
    public init(date: String, total: NutritionDayTotal, breakdown: NutritionDayBreakdown, items: [String: [NutritionMealItem]]) {
        self.date = date; self.total = total; self.breakdown = breakdown; self.items = items
    }
}

/// One row of `GET /api/v1/nutrition/daily`'s `days[]` — trimmed to what the week strip + macro
/// card need (mirrors `NutritionDailyRow` in the oracle).
public struct NutritionDailyRow: Codable, Sendable, Equatable {
    public var date: String
    public var kcalConsumed, kcalGoal, proteinG, carbsG, fatG: Double?
    public var mealsLogged: Int?
    public init(date: String, kcalConsumed: Double? = nil, kcalGoal: Double? = nil, proteinG: Double? = nil, carbsG: Double? = nil, fatG: Double? = nil, mealsLogged: Int? = nil) {
        self.date = date; self.kcalConsumed = kcalConsumed; self.kcalGoal = kcalGoal; self.proteinG = proteinG; self.carbsG = carbsG; self.fatG = fatG; self.mealsLogged = mealsLogged
    }
}

/// `GET /api/v1/nutrition/daily` (window form) — see `app/nutrition/router.py`'s
/// `NutritionReportResponse`. Only `days` is needed by this screen; other aggregate fields are
/// dropped at decode (the hub response allows extra keys server-side, and `Decodable` here simply
/// doesn't declare them).
public struct NutritionReportResponse: Codable, Sendable, Equatable {
    public var days: [NutritionDailyRow]
    public init(days: [NutritionDailyRow]) { self.days = days }
}

/// Mirrors `MealSlot` in the oracle (`mobile/src/data/types.ts`).
public enum MealSlot: String, Codable, Sendable, CaseIterable {
    case breakfast, lunch, dinner, snack
}

/// PINNED FOOD-LOG CONTRACT body (`POST /api/v1/nutrition/log`) — either a manual `items` list or
/// a one-tap `template`, mirroring the oracle's `LogFoodBody` union as one flexible struct (the
/// hub's `LogFoodBody` pydantic model already allows all fields optional/`None`).
public struct LogFoodBody: Codable, Sendable, Equatable {
    public var meal: MealSlot?
    public var items: [LogFoodItemInput]?
    public var template: String?
    public var date: String?
    public init(meal: MealSlot? = nil, items: [LogFoodItemInput]? = nil, template: String? = nil, date: String? = nil) {
        self.meal = meal; self.items = items; self.template = template; self.date = date
    }
}

public struct LogFoodItemInput: Codable, Sendable, Equatable {
    public var name: String
    public var amountG: Double?
    public var kcal: Double
    public var proteinG, carbsG, fatG: Double?
    public init(name: String, amountG: Double? = nil, kcal: Double, proteinG: Double? = nil, carbsG: Double? = nil, fatG: Double? = nil) {
        self.name = name; self.amountG = amountG; self.kcal = kcal; self.proteinG = proteinG; self.carbsG = carbsG; self.fatG = fatG
    }
}

/// One logged diary line as the hub echoes it back — carries the id `DELETE /log/{item_id}` needs.
public struct LoggedFoodItem: Codable, Sendable, Equatable {
    public var itemId: String
    public var name: String?
    public var meal: String?
    public var kcal, proteinG, carbsG, fatG: Double?
    public init(itemId: String, name: String? = nil, meal: String? = nil, kcal: Double? = nil, proteinG: Double? = nil, carbsG: Double? = nil, fatG: Double? = nil) {
        self.itemId = itemId; self.name = name; self.meal = meal; self.kcal = kcal; self.proteinG = proteinG; self.carbsG = carbsG; self.fatG = fatG
    }
}

/// `POST /api/v1/nutrition/log`'s 201 body.
public struct LogFoodResult: Codable, Sendable, Equatable {
    public var logged: [LoggedFoodItem]
    public var date: String
    public init(logged: [LoggedFoodItem], date: String) { self.logged = logged; self.date = date }
}
