import { appleAppSiteAssociation } from "@/lib/mobile-association";

export const dynamic = "force-dynamic";

export function GET() {
  return Response.json(appleAppSiteAssociation(), {
    headers: {
      "Cache-Control": "public, max-age=300",
    },
  });
}
