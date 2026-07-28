# Feature Specification — Meals and Preparation

## 1. Objective

Reduce decision fatigue and make food planning practical around irregular work and travel.

## 2. Permanent dietary rule

The default profile contains a no-eggs rule. Recipes and suggestions containing eggs are excluded unless Vanessa explicitly changes the preference in Settings.

Ingredient matching should account for obvious egg forms and user-defined exclusions. It must not claim allergen safety unless all ingredient data is verified and the product is intentionally built for that purpose.

## 3. Day contexts

- Home day
- Work day
- Travel day
- Layover
- Recovery day
- Custom

Contexts alter suggestions and preparation timing.

## 4. Meal planning

- Date-based planner
- Breakfast/lunch/dinner/snack/custom slots
- Recipe or custom meal
- Prep date/time
- Pack flag
- Refrigeration flag
- Trip link
- Notes

## 5. Recipe model

- Title
- Ingredients
- Steps
- Prep/cook time
- Servings
- Storage notes
- Refrigeration/freezer suitability
- Travel suitability
- Packing notes
- Egg-free status
- Other tags
- Favorite
- Photo

## 6. Grocery list

- Auto-add from meal plan
- Manual items
- Category grouping
- Quantity/unit
- Purchased state
- Linked meals
- Move to pantry
- Duplicate consolidation

## 7. Pantry

- Item
- Quantity
- Purchase/opened date
- Expiration/best-by date entered by user
- Storage location
- Use-before-trip flag
- Linked recipes

The app may offer suggestions from pantry data but must not assert food safety from dates alone.

## 8. Pre-trip workflow

1. Determine travel dates.
2. Identify pantry items the user marked as time-sensitive.
3. Suggest meals that use them.
4. Build grocery list.
5. Create batch-prep tasks.
6. Identify portable meals and snacks.
7. Mark prepared, packed, refrigerated, or frozen.
8. Surface relevant departure reminder.

## 9. Portable food

Each meal/snack may include:

- Portability rating entered through content metadata
- Refrigeration requirement
- Container recommendation
- Estimated storage duration entered by creator/user, without safety guarantee
- Mess level
- Prep time

## 10. Suggestions

Initial suggestions are deterministic and rule-based:

- Context
- Available time
- Pantry
- Saved preferences
- Travel/refrigeration
- Egg-free rule

Do not implement generative AI in the initial release.

## 11. Timers

- Prep timers
- Multiple named timers if practical
- Local notifications for timer completion
- Background-safe native timer behavior

## 12. Integration

- Today card
- Travel meal section
- Grocery reminder
- Pantry use-before-trip
- Progression rewards for planning/prep, not for food restriction or calorie targets

## 13. Explicit exclusions

Initial app does not require:

- Calorie counting
- Weight-loss goals
- Macro targets
- Medical diet management
- Grocery delivery integration
- Barcode nutrition database
