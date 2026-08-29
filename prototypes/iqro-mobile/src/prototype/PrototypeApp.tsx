"use client";

import { PrototypeProvider, usePrototype } from "./store";
import { AudioScreen, PlayerScreen } from "./screens/Audio";
import { HomeScreen } from "./screens/Home";
import {
  AccountScreen,
  DuaEntryScreen,
  DuaScreen,
  DuaTopicScreen,
  FavoritesScreen,
  MoreScreen,
  SettingsScreen,
} from "./screens/More";
import { OnboardingGoal, OnboardingLanguage, OnboardingNorm } from "./screens/Onboarding";
import { MemorizationScreen, PlanScreen, PrayerReadingScreen, PrayerScreen } from "./screens/Plan";
import { MushafScreen, QuranScreen, ReaderScreen } from "./screens/Quran";
import { ShareScreen } from "./features/share/ShareScreen";

function ActiveScreen() {
  const { state } = usePrototype();
  const screen = {
    "onboarding-language": <OnboardingLanguage />,
    "onboarding-goal": <OnboardingGoal />,
    "onboarding-norm": <OnboardingNorm />,
    home: <HomeScreen />,
    quran: <QuranScreen />,
    reader: <ReaderScreen />,
    mushaf: <MushafScreen />,
    audio: <AudioScreen />,
    player: <PlayerScreen />,
    plan: <PlanScreen />,
    "prayer-reading": <PrayerReadingScreen />,
    prayer: <PrayerScreen />,
    memorization: <MemorizationScreen />,
    dua: <DuaScreen />,
    "dua-topic": <DuaTopicScreen />,
    "dua-entry": <DuaEntryScreen />,
    favorites: <FavoritesScreen />,
    more: <MoreScreen />,
    account: <AccountScreen />,
    share: <ShareScreen />,
    settings: <SettingsScreen />,
  }[state.route];

  return (
    <div className="prototype-stage">
      <div className="prototype-notes" aria-hidden="true">
        <span className="eyebrow">IQRO · Mobile UX</span>
        <h1>One calm rhythm.<br/>Every day.</h1>
        <p>Interactive product prototype<br/>RU · EN · AR RTL · TR</p>
        <div className="note-swatches"><i/><i/><i/><i/></div>
      </div>
      <div className="device-shell" data-screen={state.route}>
        <div className="device-status" aria-hidden="true"><span>9:41</span><span className="status-island"/><span className="status-icons"><i/><i/><b/></span></div>
        {screen}
      </div>
      <div className="prototype-caption" aria-hidden="true"><span>390 × 844</span><span>Safe area · Dynamic Type · 44px targets</span></div>
    </div>
  );
}

export function PrototypeApp() {
  return <PrototypeProvider><ActiveScreen /></PrototypeProvider>;
}
