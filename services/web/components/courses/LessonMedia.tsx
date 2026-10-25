import { isLocale, type Locale } from "@/lib/i18n";
import { LESSON_MEDIA_SIZES, lessonImageSrcSet, type CourseMediaBlock } from "@/lib/thematic-courses";
import { translate } from "@/lib/translate";

import { LessonSlides } from "./LessonSlides";
import { LessonVideo } from "./LessonVideo";

/**
 * Lesson media above the notes, in the author's order: the video player, slides and banners.
 * Only the slides need client JS; a banner is plain server HTML.
 */
export function LessonMedia({
  blocks,
  locale,
  language,
  courseSlug,
  lessonSlug,
  title,
}: {
  blocks: CourseMediaBlock[];
  locale: Locale;
  /** The language of the document; a video speaking another one says so. */
  language: string;
  /** Where the video remembers its position: `courses.position.<courseSlug>`. */
  courseSlug: string;
  lessonSlug: string;
  title: string;
}) {
  if (!blocks.length) return null;
  // The first slide or banner is likely the largest paint, even below the video's cover on a phone.
  const firstPicture = blocks.findIndex((block) => block.type !== "video");
  // A report names a slide by its number in the whole lesson: the carousels count on.
  const firstSlides = blocks.map((_, index) =>
    blocks.slice(0, index).reduce((count, block) => count + (block.type === "slides" ? block.slides.length : 0), 1));
  return (
    <div className="lesson-media">
      {blocks.map((block, index) => {
        const first = index === firstPicture;
        switch (block.type) {
          case "video": {
            // The server already chose the file for this language; a video in another one says so.
            const spoken = block.video.spoken_language;
            const otherLanguage = spoken && spoken !== language && isLocale(spoken) ? spoken : null;
            return (
              <div key={index} className="course-lesson-video">
                <LessonVideo courseSlug={courseSlug} lessonSlug={lessonSlug} title={title} video={block.video} />
                {otherLanguage ? (
                  <p className="course-lesson-video-language" data-testid="lesson-video-language">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"
                      strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                      <circle cx="12" cy="12" r="9" />
                      <path d="M3 12h18M12 3c2.5 2.6 3.8 5.6 3.8 9s-1.3 6.4-3.8 9c-2.5-2.6-3.8-5.6-3.8-9S9.5 5.6 12 3z" />
                    </svg>
                    {translate(locale, `courses.videoLanguage.${otherLanguage}`)}
                  </p>
                ) : null}
              </div>
            );
          }
          case "slides":
            return (
              <LessonSlides
                key={index}
                slides={block.slides}
                priority={first}
                report={{ courseSlug, lessonSlug, firstNumber: firstSlides[index]! }}
              />
            );
          case "banner":
            return (
              <figure key={index} className="lesson-banner" data-testid="lesson-banner">
                {/* eslint-disable-next-line @next/next/no-img-element -- a ready 16:9 WebP from the media host */}
                <img
                  src={block.image.small_url}
                  srcSet={lessonImageSrcSet(block.image)}
                  sizes={LESSON_MEDIA_SIZES}
                  width={block.image.width}
                  height={block.image.height}
                  alt={block.alt}
                  decoding="async"
                  loading={first ? undefined : "lazy"}
                  fetchPriority={first ? "high" : undefined}
                />
                {block.caption ? <figcaption dir={block.dir}>{block.caption}</figcaption> : null}
              </figure>
            );
        }
      })}
    </div>
  );
}
