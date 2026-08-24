import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Quran Platform",
    short_name: "Quran",
    description: "Read the Quran, listen to reciters, and calculate prayer times.",
    start_url: "/",
    display: "standalone",
    background_color: "#f6f8f7",
    theme_color: "#065f46",
    orientation: "any",
    icons: [
      {
        src: "/icon",
        sizes: "512x512",
        type: "image/png",
      },
    ],
  };
}
