export type LegalConfig = {
  entityName: string;
  contactEmail: string;
  securityEmail: string;
  postalAddress: string;
  jurisdiction: string;
  effectiveDate: string;
};

function value(name: string, fallback: string): string {
  return process.env[name]?.trim() || fallback;
}

export function legalConfig(): LegalConfig {
  return {
    entityName: value("LEGAL_ENTITY_NAME", "Mr.Fulani (Iqro-Forum project)"),
    contactEmail: value("LEGAL_CONTACT_EMAIL", "iqro.forum@gmail.com"),
    securityEmail: value("SECURITY_CONTACT_EMAIL", "iqro.forum@gmail.com"),
    postalAddress: value("LEGAL_POSTAL_ADDRESS", "Configure LEGAL_POSTAL_ADDRESS before launch"),
    jurisdiction: value("LEGAL_JURISDICTION", "Türkiye"),
    effectiveDate: value("LEGAL_EFFECTIVE_DATE", "2026-08-24"),
  };
}
