import React, { useState, useEffect, lazy, Suspense } from 'react';
import { BrowserRouter as Router, Route, Routes } from 'react-router-dom';
import './App.css';
import HeaderBar from './components/HeaderBar';
import FooterBar from './components/FooterBar';
import SEO from './components/SEO';
import StructuredData from './components/StructuredData';

// Lazy load all components
const LazyLandingHeader = lazy(() => import('./components/LandingHeader'));
const LazyIndustryPainpoints = lazy(() => import('./components/IndustryPainpoints'));
const LazyHowItWorks = lazy(() => import('./components/HowItWorks'));
const LazyTheAutomationSpeaks = lazy(() => import('./components/TheAutomationSpeaks'));
const LazySocialValidation = lazy(() => import('./components/SocialValidation'));
const LazyFAQSection = lazy(() => import('./components/FAQSection'));
const LazySecondCTA = lazy(() => import('./components/SecondCTA'));
const LazyContactPage = lazy(() => import('./components/ContactPage'));

function App() {
  const [config, setConfig] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    fetch(`${process.env.PUBLIC_URL}/config.json`)
      .then(response => {
        if (!response.ok) {
          throw new Error(`HTTP error! status: ${response.status}`);
        }
        return response.json();
      })
      .then(data => {
        setConfig(data);
        // Initialize Google Analytics
        if (data.gaTrackingId) {
          initializeGoogleAnalytics(data.gaTrackingId);
        }
      })
      .catch(error => {
        console.error('Error loading config:', error);
        setError(error.message);
      });
  }, []);

  const initializeGoogleAnalytics = (trackingId) => {
    // Create script elements
    const gtmScript = document.createElement('script');
    gtmScript.async = true;
    gtmScript.src = `https://www.googletagmanager.com/gtag/js?id=${trackingId}`;

    const inlineScript = document.createElement('script');
    inlineScript.innerHTML = `
      window.dataLayer = window.dataLayer || [];
      function gtag(){dataLayer.push(arguments);}
      gtag('js', new Date());
      gtag('config', '${trackingId}');
    `;

    // Append scripts to body
    document.body.appendChild(gtmScript);
    document.body.appendChild(inlineScript);
  };

  if (error) {
    return <div>Error loading configuration: {error}</div>;
  }

  if (!config) {
    return <div>Loading...</div>;
  }

  return (
    <Router>
      <div className="App">
        <SEO config={config} />
        <StructuredData config={config} />
        <HeaderBar 
          header={config.header} 
          icon={config.icon} 
        />
        <Routes>
          <Route path="/" element={
            <Suspense fallback={<div>Loading...</div>}>
              <LazyLandingHeader
                title={config.title}
                description={config.description}
                buttonText={config.buttonText}
                buttonLink={config.contactPageLink}
                userReviews={config.userReviews}
                videoUrl={config.videoUrl}
                imageUrl={config.imageUrl}
              />
              <LazyIndustryPainpoints
                title={config.painpointsTitle}
                painpoints={config.painpoints}
                contactFormOptions={config.contactFormOptions}
                shortParagraph={config.shortParagraph}
                domainName={config.domainName}
                contactFormLambdaUrl={config.contactFormLambdaUrl}
              />
              <LazyTheAutomationSpeaks
                title={config.theAutomationSpeaksTitle}
                text={config.theAutomationSpeaksText}
                image={config.theAutomationSpeaksImage}
              />
              <LazyHowItWorks
                title={config.howItWorksTitle}
                description={config.howItWorksDescription}
                steps={config.howItWorksSteps}
              />
              <LazySocialValidation
                title={config.socialValidationTitle}
                text={config.socialValidationText}
              />
              <LazyFAQSection
                title={config.faqTitle}
                faqItems={config.faqItems}
              />
              <LazySecondCTA
                title={config.secondCtaTitle}
                testimonial={config.secondCtaTestimonial}
                buttonText={config.secondCtaButtonText}
                buttonLink={config.contactPageLink}
                users={config.secondCtaUsers}
              />
            </Suspense>
          } />
          <Route path={config.contactPageLink} element={
            <Suspense fallback={<div>Loading...</div>}>
              <LazyContactPage
                contactFormOptions={config.contactFormOptions}
                domainName={config.domainName}
                contactFormLambdaUrl={config.contactFormLambdaUrl}
                calendlyUrl={config.calendlyUrl}
                title={config.contactPageTitle}
                blurb={config.contactPageBlurb}
                contactFormTitle={config.contactFormTitle}
                scheduleCallTitle={config.scheduleCallTitle}
              />
            </Suspense>
          } />
        </Routes>
        <FooterBar footerText={config.footerText} />
      </div>
    </Router>
  );
}

export default App;
