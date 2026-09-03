import { androidAssetLinks } from "@/lib/mobile-association";

export const dynamic = "force-dynamic";

export function GET() {
  return Response.json(androidAssetLinks(), {
    headers: {
      "Cache-Control": "public, max-age=300",
    },
  });
}
