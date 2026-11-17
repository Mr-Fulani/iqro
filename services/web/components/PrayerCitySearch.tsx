"use client";

import { useEffect, useId, useRef, useState } from "react";
import { api, PrayerCity } from "../lib/api";
import { useI18n } from "../lib/i18n-context";

/**
 * Finds a city for the prayer times by the start of its name, in our own
 * copy of GeoNames on the server (GET /api/v1/prayer/cities), as the app's
 * city search does. Nothing found, or no connection: the quick list and
 * «my location» still work.
 */
export function PrayerCitySearch({ onPick }: { onPick: (city: PrayerCity) => void }) {
  const { locale, t } = useI18n();
  const inputId = useId();
  const listId = useId();
  const [query, setQuery] = useState("");
  const [cities, setCities] = useState<PrayerCity[] | null>(null);
  // Only the answer to the latest typing is shown.
  const request = useRef(0);

  useEffect(() => {
    const typed = query.trim();
    const current = ++request.current;
    if (typed.length < 2) {
      setCities(null);
      return;
    }
    const timer = window.setTimeout(() => {
      api.searchPrayerCities(typed, locale)
        .then((found) => {
          if (current === request.current) setCities(found);
        })
        .catch(() => {
          if (current === request.current) setCities(null);
        });
    }, 300);
    return () => window.clearTimeout(timer);
  }, [locale, query]);

  const countries = (() => {
    try {
      return new Intl.DisplayNames([locale], { type: "region" });
    } catch {
      return null;
    }
  })();

  return (
    <div className="form-group prayer-city-search" data-testid="prayer-city-search">
      <label className="form-label" htmlFor={inputId}>{t("prayer.citySearch")}</label>
      <input
        id={inputId}
        type="search"
        value={query}
        onChange={(event) => setQuery(event.target.value)}
        autoComplete="off"
        aria-controls={listId}
        maxLength={80}
      />
      <div id={listId} aria-live="polite">
        {cities?.length === 0 && <p className="field-help">{t("prayer.cityNotFound")}</p>}
        {cities && cities.length > 0 && (
          <ul className="prayer-city-results">
            {cities.map((city) => (
              <li key={city.id}>
                <button
                  type="button"
                  onClick={() => {
                    request.current += 1;
                    setCities(null);
                    setQuery(city.name);
                    onPick(city);
                  }}
                >
                  <strong>{city.name}</strong>
                  <small>{countries?.of(city.country_code) ?? city.country_code}</small>
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
