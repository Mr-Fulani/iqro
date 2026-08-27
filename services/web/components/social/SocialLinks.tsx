import type { SocialProfile } from "../../lib/api";
import { SocialIcon } from "./SocialIcon";

type SocialLinksProps = {
  profiles: SocialProfile[];
  ariaLabel: string;
  className?: string;
  showAccountNames?: boolean;
};

export function SocialLinks({
  profiles,
  ariaLabel,
  className = "",
  showAccountNames = true,
}: SocialLinksProps) {
  if (profiles.length === 0) return null;

  return (
    <nav className={`social-links ${className}`.trim()} aria-label={ariaLabel}>
      <ul className="social-links-list">
        {profiles.map((profile) => {
          const accessibleName = profile.display_name
            ? `${profile.platform_name}: ${profile.display_name}`
            : profile.platform_name;
          return (
            <li key={profile.platform}>
              <a
                className="social-link"
                data-platform={profile.platform}
                href={profile.url}
                target="_blank"
                rel={profile.include_in_seo ? "me noopener noreferrer" : "noopener noreferrer"}
                aria-label={accessibleName}
                title={accessibleName}
              >
                <span className="social-link-icon"><SocialIcon platform={profile.platform} /></span>
                <span className="social-link-copy">
                  <strong>{profile.platform_name}</strong>
                  {showAccountNames && profile.display_name ? <small>{profile.display_name}</small> : null}
                </span>
                <span className="social-link-external" aria-hidden="true">↗</span>
              </a>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
