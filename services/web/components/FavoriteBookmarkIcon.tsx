export function FavoriteBookmarkIcon({ active = false }: { active?: boolean }) {
  return (
    <svg className="favorite-bookmark-icon" viewBox="0 0 24 24" aria-hidden="true">
      <path
        d="M5.75 3.75h12.5c.55 0 1 .45 1 1v15.5L12 16.2l-7.25 4.05V4.75c0-.55.45-1 1-1Z"
        fill={active ? "currentColor" : "none"}
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.8"
      />
    </svg>
  );
}
