# Kharcha

An expense tracker for Android and iOS. It shows where your money goes and finds specific ways to save, with an AI coach powered by Claude.

Built with Flutter (one codebase for Android, iOS and web) and Supabase (login, Postgres database, server functions).

## What works today

- **Add an expense in seconds:** keypad, note, category, date and payment method. Typing a note like "petrol" or "Swiggy" picks the category for you.
- **Your own categories:** pick **Other** and name it ("Gifts"). It becomes a category you can budget.
- **Quick add:** your usual spends from the last 30 days, one tap to repeat.
- **Home:** spent this month, budget used, safe to spend today, month-end forecast, the top saving tip, and recent expenses.
- **Insights:** money leaks and habits with the ₹ you'd save, plus a daily spending chart.
  - Leaks found include price rises, double charges, too many video apps, late-night orders, café runs and late fees.
- **AI savings plan and Ask AI chat:** Claude reads your month and answers in a few short lines.
- **Budgets:** per-category limits, "On track / Likely over / Over" status, and one-tap suggested budgets.
- **Motion throughout:** rolling numbers, rings and bars that draw themselves, and a success burst when you add an expense. All motion turns off when the phone's "reduce motion" setting is on.
- **Demo mode:** with no backend configured, the app runs on two months of example data.

## Project layout

```
lib/
  core/money.dart            ₹ formatting (Indian digit grouping), dates
  data/                      models, demo + Supabase repositories, example data
  domain/analysis.dart       totals, forecast, safe-to-spend, money-leak rules
  domain/category_guess.dart note → category
  services/ai_coach.dart     calls the ai-coach server function
  state/app_state.dart       Riverpod state with instant (optimistic) updates
  ui/                        screens, theme, motion widgets
supabase/
  migrations/                database schema + row-level security
  functions/ai-coach/        server function that calls Claude
  tests/                     schema + security tests (plain Postgres)
test/                        unit + widget tests
```

## Run it

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.47 or newer).

Demo mode (no backend, example data):

```bash
flutter pub get
```

```bash
flutter run
```

Tests:

```bash
flutter test
```

## Connect the real backend

1. **Create a Supabase project** at [supabase.com](https://supabase.com). In **Settings → API**, copy the project URL and the publishable key.

2. **Create the tables.** Either paste `supabase/migrations/20261109000000_init.sql` into the SQL editor and run it, or use the Supabase CLI:

   ```bash
   supabase link --project-ref YOUR_PROJECT_REF
   ```

   ```bash
   supabase db push
   ```

3. **Turn on email codes.** In **Authentication → Email templates → Magic link**, make sure the template includes `{{ .Token }}`, so users get a 6-digit code.

4. **Turn on AI.** Get an API key from the [Claude Console](https://platform.claude.com), then:

   ```bash
   supabase secrets set ANTHROPIC_API_KEY=your-key
   ```

   ```bash
   supabase functions deploy ai-coach
   ```

   The function uses `claude-opus-5-5` by default. To use another model, set `CLAUDE_MODEL`. Daily AI limits per plan (free 10, pro 100, family 200) are at the top of `supabase/functions/ai-coach/index.ts`.

5. **Run the app against it:**

   ```bash
   flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
   ```

### Security

- Every table has row-level security, so a user can only read or change their own rows.
- Users cannot change their own plan.
- The Claude API key lives only on the server. The app never holds it.
- `supabase/tests/run_local.sh` checks these rules against a local Postgres.

## Build for phones

Android (needs the Android SDK):

```bash
flutter build apk --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
```

iOS (needs a Mac with Xcode):

```bash
flutter build ipa --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
```

Before store release, set your own app id (currently `app.kharcha`), icons and signing keys.

## Next up

- Voice entry, receipt scan, bank SMS and statement import
- Recurring expense detection from real data
- Paid plans and payments
- Push notifications for budget alerts

Fonts: Figtree and Familjen Grotesk, both under the SIL Open Font License.
