import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "IQRO",
    short_name: "IQRO",
    description: "Read the Quran, listen to reciters, and calculate prayer times.",
    start_url: "/",
    display: "standalone",
    background_color: "#f6f8f7",
    theme_color: "#065f46",
    orientation: "any",
    icons: [
      {
        src: "/iqro-app-icon.png",
        sizes: "512x512",
        type: "image/png",
      },
    ],
  };
}
