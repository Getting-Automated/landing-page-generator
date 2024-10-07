import React from 'react';
import { Helmet } from 'react-helmet';
import { useLocation } from 'react-router-dom';

const SEO = ({ config }) => {
  const location = useLocation();
  const isHomePage = location.pathname === '/';

  const title = isHomePage ? config.seoTitle : `${config.contactPageTitle} | ${config.seoTitle}`;
  const description = isHomePage ? config.seoDescription : config.contactPageBlurb;
  const url = `${config.domainName}${location.pathname}`;

  return (
    <Helmet>
      <title>{title}</title>
      <meta name="description" content={description} />
      <link rel="canonical" href={url} />
      
      <meta property="og:title" content={title} />
      <meta property="og:description" content={description} />
      <meta property="og:image" content={config.ogImage} />
      <meta property="og:url" content={url} />
      <meta property="og:type" content="website" />
      
      <meta name="twitter:card" content="summary_large_image" />
      <meta name="twitter:title" content={title} />
      <meta name="twitter:description" content={description} />
      <meta name="twitter:image" content={config.ogImage} />
    </Helmet>
  );
};

export default SEO;