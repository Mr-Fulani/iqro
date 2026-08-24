import { ImageResponse } from "next/og";

export const size = { width: 512, height: 512 };
export const contentType = "image/png";

export default function Icon() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          background: "linear-gradient(145deg, #064e3b, #0f766e)",
          color: "#ffffff",
          fontSize: 300,
          fontWeight: 700,
          letterSpacing: -24,
        }}
      >
        Q
      </div>
    ),
    size,
  );
}
