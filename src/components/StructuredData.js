import React from 'react';
import { Helmet } from 'react-helmet';

const StructuredData = ({ config }) => {
  const websiteSchema = {
    "@context": "https://schema.org",
    "@type": "WebSite",
    "name": config.title,
    "description": config.description,
    "url": config.domainName
  };

  const faqSchema = {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    "mainEntity": config.faqItems.map(item => ({
      "@type": "Question",
      "name": item.question,
      "acceptedAnswer": {
        "@type": "Answer",
        "text": item.answer
      }
    }))
  };

  return (
    <Helmet>
      <script type="application/ld+json">
        {JSON.stringify(websiteSchema)}
      </script>
      <script type="application/ld+json">
        {JSON.stringify(faqSchema)}
      </script>
    </Helmet>
  );
};

export default StructuredData;