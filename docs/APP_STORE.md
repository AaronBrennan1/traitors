# App Store listing

Everything to paste into App Store Connect for version 1.0. Character limits are Apple's; the
counts beside each field are for the text as written here.

## Name (30 max)

```
Traitors
```

## Subtitle (30 max)

```
Eight players. Two traitors.
```

## Promotional text (170 max)

This is the one field you can change without a new build, so it is the place for news later on.

```
Seven sharp rivals, two hidden traitors and a castle full of games. Play the day's mission, argue your case at the Round Table and try to see out the night.
```

## Description (4,000 max)

```
Traitors is a single-player game of social deduction. Eight players arrive at a castle. Two are secretly traitors, and you may be one of them.

Each day the group plays a real-time mission together, then meets at the Round Table to debate and vote one player out. If the mission falls short, the traitors remove one of the faithful that night. The faithful win by banishing both traitors. The traitors win by surviving to the end.

• Seven computer-controlled rivals, each with a distinct personality, who reason only from what they have seen and heard
• Fifteen real-time missions, where what happens becomes the evidence debated at the table
• Play as faithful or traitor, or let the game decide
• A post-game breakdown of how suspicious you looked and what each player thought of you
• Fully offline, with no ads, accounts or in-app purchases
• Supports VoiceOver and Reduce Motion, on iPhone and iPad
```

## Keywords (100 max, commas, no spaces)

Words already in the name and subtitle are indexed, so they are left out here.

```
social deduction,mafia,werewolf,bluff,betrayal,murder,vote,offline,solo,strategy,minigames,irish
```

## What's New (version 1.0)

```
First release. Take your seat.
```

## Categories and rating

| Field | Value |
|---|---|
| Primary category | Games, Strategy |
| Secondary category | Games, Action |
| Age rating | Answer the questionnaire as: cartoon or fantasy violence, infrequent or mild. Nothing else applies. Expect 9+. |
| Price | Your call. The copy above says there are no in-app purchases, which holds either way. |
| Copyright | `2026 Aaron Brennan` |

## App Privacy

The app has no networking, analytics, advertising or account code. Saves, stats and settings stay
on the device.

- Data collection: **Data Not Collected**
- Tracking: **No**

A privacy policy URL is still required. This is enough to host on a single page:

```
Privacy Policy

Traitors does not collect, store or share any personal information.

The game runs entirely on your device. Your saved game, your statistics, your settings and the name you type for your player are stored on your device only and are never sent anywhere. The app contains no advertising, no analytics and no third-party tracking.

If you delete the app, this data is deleted with it.

Questions: aaronbrennan.brennan@gmail.com

Last updated 9 October 2026.
```

A support URL is also required. The same page with a contact address will do.

## Notes for App Review

```
Traitors is a single-player game and works fully offline. There is no sign-in, no account and no purchase.

To see it quickly: tap "New game" on the title screen, enter any name, choose a side and tap "Enter the castle". A short tutorial plays first and can be paged through. The first mission follows the role reveal and breakfast.

The seven other players are computer-controlled. Their names and occupations are fictional.
```

## Screenshots

Required sets: 6.9" iPhone (1320 × 2868, portrait) and 13" iPad (2064 × 2752), because the app
ships for both. Up to ten each. The first three show in search results, so they carry the pitch.

| # | Screen | Caption |
|---|---|---|
| 1 | Role reveal, as a traitor | Eight players. Two traitors. Are you one? |
| 2 | Round Table, mid-accusation with an evidence chip chosen | Make your case. Then vote. |
| 3 | A gauntlet course in play (the Great Hall, blades swinging) | Play the mission together. |
| 4 | A second game that looks different (Sheep Round-Up or the Shipwreck Dive) | Fifteen missions, each with its own twist. |
| 5 | Take your seat, showing "Your seven rivals" | Seven rivals who reason for themselves. |
| 6 | Night, choosing a victim | Lie by day. Choose by night. |
| 7 | Game over, the suspicion chart | See what they really thought of you. |

Set captions in the serif the game uses, parchment (#EDE6D1) on the game's dark green
(#080C0B), with gold (#D6B35C) for one emphasised word at most.

`docs/ARCHITECTURE.md` lists launch arguments that jump straight to the demonstration reels and
tutorial pages (`-demo all`, `-demo kiteRace`, `-autoplay 1 -tutorial 1 -tutorialPage n`), which
saves playing to each screen by hand.

An app preview video is optional. If you make one, 20 seconds is plenty: role reveal, ten seconds
of a mission, one accusation, the banishment reveal.

## Before you submit

Three things to settle before submitting.

1. **The name.** The listing uses "Traitors", as decided. The risk stands: *The Traitors* is a
   registered trademark and a licensed format, and Apple's guideline 5.2.1 does not accept a
   disclaimer in place of permission. The title screen's "fan-made, not affiliated with the
   television programme" line points the reviewer straight at the comparison. The name must
   also be unused on the App Store, which has not been checked.
2. **The icon.** The masks look like the SF Symbol `theatermasks.fill`, the same glyph the title
   screen uses. Apple's licence for SF Symbols does not allow them in app icons. Redraw the
   masks, or use a different mark (a candle, a key, a hooded figure) on the same green and gold.
3. **The category.** The project sets `LSApplicationCategoryType` to
   `public.app-category.entertainment`. Change it to `public.app-category.strategy-games` so the
   build agrees with the listing.
