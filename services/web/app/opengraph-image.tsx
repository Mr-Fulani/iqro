import { ImageResponse } from "next/og";

export const alt = "Quran Platform — read, listen, and plan";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpenGraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          padding: "72px 88px",
          background: "linear-gradient(135deg, #052e2b 0%, #065f46 56%, #0f766e 100%)",
          color: "white",
          fontFamily: "sans-serif",
        }}
      >
        <div style={{ display: "flex", flexDirection: "column", maxWidth: 780 }}>
          <div style={{ color: "#a7f3d0", fontSize: 28, letterSpacing: 5, textTransform: "uppercase" }}>
            Madani Mushaf · Quran Audio · Prayer
          </div>
          <div style={{ display: "flex", fontSize: 82, fontWeight: 700, marginTop: 28 }}>
            Quran Platform
          </div>
          <div style={{ display: "flex", fontSize: 36, lineHeight: 1.35, marginTop: 24, color: "#d1fae5" }}>
            Read the Quran, listen to reciters, and keep your progress synchronized.
          </div>
        </div>
        <div
          style={{
            width: 220,
            height: 220,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            borderRadius: 56,
            background: "rgba(255, 255, 255, 0.14)",
            border: "3px solid rgba(255, 255, 255, 0.28)",
            fontSize: 142,
            fontWeight: 700,
          }}
        >
          Q
        </div>
      </div>
    ),
    size,
  );
}
