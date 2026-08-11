# Meals

Implemented in Phase 6. Meals includes the day planner, recipes, permanent
egg-free filtering, grocery and pantry workflows, preparation tasks, durable
kitchen timers, packed food, use-before-trip suggestions, and travel context.

```
Meals/
├── Screens/MealsScreen.swift
├── Screens/MealDetailScreens.swift
├── Screens/GroceryAndPantryScreens.swift
├── UseCases/ManageMeals.swift
└── UseCases/ManageGroceryAndPantry.swift
```

The feature never scores food, counts calories, or rewards restriction. Recipe
eligibility is enforced in shared domain logic, not only hidden by the UI.
