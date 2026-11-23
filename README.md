# Konstis kesser Triathlon 🏊‍♂️🚴‍♂️🏃‍♂️

Private iOS-Trainings-App (Swift/SwiftUI) zur Vorbereitung auf Konstis Triathlon.

## Features

- **Pixel-Konsti** im Schwimm-, Rad- oder Lauf-Outfit (passend zur heutigen Einheit, Tippen wechselt das Outfit). Er wird mit jeder Stufe kesser: Medaille, Glitzer, goldene Aura, Krone.
- **Leveling**: Level 1–20 in vier Stufen: *Frischling → Durchhalter → Ausdauer-Ass → Kesser Konsti*. XP = Minuten × Intensität (+ Bonus, wenn's zum Plan passt). Wer den Plan durchzieht, ist am Wettkampftag Level 20.
- **Pixel-Cheerleaderin** feuert an: bei Trainings-Meilensteinen (1., 5., 10., 25., … Training), neuen Bestmarken (längste Einheit) und Bestzeiten (schnellstes Tempo), Level-Ups, komplett erledigten Wochen und Countdown-Marken (100, 50, 30, 14, 7, 1 Tag).
- **Trainingsplan** pro Tag und Woche, periodisiert: Grundlage → Aufbau → Spitze → Tapering → Wettkampfwoche, jede 4. Woche Entlastung. Richtet sich nach Distanz, **Trainingstagen pro Woche**, **Arbeitstagen/-zeiten**, festen Ruhetagen und Zeitbudget.
- **Start-Animation** mit Pixel-Konsti beim Schwimmen, Radfahren und Laufen.
- **Fortschrittsbalken** pro Disziplin (Wettkampf-Form aus längster Einheit vs. Wettkampfdistanz und Plantreue der letzten 4 Wochen), Wochen-Chart, Verlauf.
- **Trainings eintragen, verschieben, auslassen**, mit Zeit, Distanz und **Ampel** für Stimmung und gefühlte Schwere.
- **Countdown** bis zum Wettkampf.
- **Apple Health / Apple Watch**: Schwimm-, Rad- und Lauf-Workouts (auch der Triathlon-/Multisport-Modus, wird in die Einzeldisziplinen zerlegt) werden beim Öffnen der App automatisch übernommen und mit dem Plan abgeglichen.
- **Adaptive Vorschläge**: Was ist heute sinnvoll? Berücksichtigt Plan, verpasste Schlüsseleinheiten, freie Zeit laut **Kalender** (Arbeitstermine), Ermüdung (rote Ampeln, plötzlicher Umfangssprung) und die schwächste Disziplin. Bei vollem Kalender schlägt die App einen besseren Tag vor.

## Auf dem iPhone installieren

Voraussetzungen: Mac mit **Xcode 16 oder neuer**, iPhone mit iOS 17+, eine (kostenlose) Apple-ID.

1. Repo klonen und `KesserTriathlon.xcodeproj` in Xcode öffnen.
2. Links das Projekt **KesserTriathlon** anklicken → Target **KesserTriathlon** → Tab **Signing & Capabilities**.
3. Bei **Team** deine Apple-ID auswählen (ggf. erst unter *Xcode › Settings › Accounts* hinzufügen).
4. **Bundle Identifier** eindeutig machen, z. B. `de.deinname.kessertriathlon` (der vorgegebene ist evtl. schon vergeben).
5. Prüfen, dass unter Capabilities **HealthKit** steht (ist über die Entitlements-Datei schon gesetzt).
6. iPhone per Kabel anschließen, oben als Ziel auswählen und **▶︎ Run** drücken.
7. Beim ersten Mal auf dem iPhone: *Einstellungen › Datenschutz & Sicherheit › Entwicklermodus* aktivieren (Neustart), danach *Einstellungen › Allgemein › VPN & Geräteverwaltung* → deinem Entwicklerzertifikat vertrauen.

Hinweis: Mit einer **kostenlosen** Apple-ID läuft die App 7 Tage, danach einfach wieder aus Xcode starten (Daten bleiben erhalten). Mit dem bezahlten Developer Program ist es 1 Jahr.

## In der App

1. Onboarding: Wettkampf (Name, Datum, Distanz), Ruhetage und Zeitbudget festlegen, Apple Health und Kalender verbinden → Plan wird erstellt.
2. Training mit der Watch aufzeichnen wie immer. Beim Öffnen der App landet es automatisch unter „Wie war's?“, dort nur noch die Ampel setzen.
3. Planänderungen (Datum, Distanz, Trainingstage, Arbeitszeiten): in den Einstellungen ändern, dann oben auf *Plan jetzt neu erstellen*. Nach App-Updates mit neuer Plan-Logik passiert das automatisch. Erledigte und selbst bearbeitete Einheiten bleiben erhalten.

## Projektstruktur

```
KesserTriathlon/
  App/        App-Einstieg, Tabs, Cheerleader-Overlay
  Models/     SwiftData-Modelle (Profil, geplante & absolvierte Trainings), Enums
  Logic/      PlanGenerator, ProgressEngine (Leveling), SuggestionEngine, CheerEngine
  Services/   HealthKitManager, CalendarManager, WorkoutSync
  Views/      Heute, Plan, Fortschritt, Einstellungen, Sheets, Komponenten
  Assets.xcassets  Pixel-Konsti-Sprites, Cheerleaderin, App-Icon
Config/       Info.plist (Datenschutztexte), Entitlements (HealthKit)
```

Alle Daten bleiben lokal auf dem iPhone (SwiftData). Kein Server, kein Tracking.
