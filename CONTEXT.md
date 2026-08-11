# Game Completion Tracker (游戏通关记录)

A personal macOS app for recording video games the user has finished, including cover art, four-dimension scores, and per-playthrough notes.

## Language

**Game 游戏**: A library entry representing one finished video game. Holds the name, aliases, the release date, the cover, and the review.
_Avoid_: Title, record, entry

**Alias 别名**: An alternate name for a Game, set on its detail page and used by search. A Game can have several (e.g. English and Chinese titles).
_Avoid_: Nickname, aka, keyword

**Release Date 发售日期**: The day the Game was released. Used to sort the library.
_Avoid_: Launched, shipped

**Group 分组**: A user-defined collection of Games, typically a series, used to organize the library. A Game can belong to several Groups.
_Avoid_: Collection, tag, folder, category

**Completion 通关记录**: A single playthrough of a Game that the user finished. Holds platform, completion date, completion degree, playtime, notes, and optionally scores. Appended to its Game after finishing.
_Avoid_: Playthrough, 通关

**Completion Degree 通关程度**: How thoroughly a Completion finished the game. Chosen from presets (main story, all endings, platinum…) or a custom value.
_Avoid_: Progress, status

**Platform 平台**: Where the Game was played for a given Completion. Chosen from presets (PC, Switch, PlayStation…) or a custom value.
_Avoid_: System, console

**Playtime 时长**: How long the user spent on one Completion, in hours with one decimal place.
_Avoid_: Hours, time played

**Dimension Scores 四维评分**: The four scores (1–10, slider with 0.1 steps) on a Completion for Story 剧情, Graphics 画面, Music 音乐, and Gameplay 玩法. Required on a Game's first Completion, optional on later ones.
_Avoid_: Ratings, stars

**Record Average 平均总分**: The arithmetic mean of the four Dimension Scores of a single Completion, displayed rounded to the nearest 0.5.
_Avoid_: Score

**Library Score 库显示分**: The score displayed for a Game in the library. It is the mean of the Record Averages of every scored Completion of that Game, displayed rounded to the nearest 0.5; blank if no Completion is scored.
_Avoid_: Total, grade

**Cover 封面**: The game's cover image. Imported manually or fetched from the SteamGridDB API.
_Avoid_: Art, image, poster

**Completion Notes 通关内容**: Free-text notes the user writes about one specific Completion.
_Avoid_: Memo, journal, diary

**Review 评价**: The user's long-form opinion of the Game itself, not of any single playthrough. Has a short **title** (required when the Game is first created; the one-line verdict shown on the Share Card) and a full **body** (always optional).
_Avoid_: Comment, feedback, review text

**Share Card 分享图**: An exported image at phone or desktop dimensions for posting to Weibo or Twitter. Selecting a single Game renders one card for that Game; selecting several renders one combined overview image of all of them. The card style follows the macOS system appearance (light/dark); the overview image's top title is user-customizable.
_Avoid_: Export, screenshot, card
