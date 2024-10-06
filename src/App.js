import React, { useState, useEffect } from 'react';
import { BrowserRouter as Router, Route, Routes } from 'react-router-dom';
import ReactGA from 'react-ga4';
import './App.css';
import HeaderBar from './components/HeaderBar';
import LandingHeader from './components/LandingHeader';
import IndustryPainpoints from './components/IndustryPainpoints';
import HowItWorks from './components/HowItWorks';
import TheAutomationSpeaks from './components/TheAutomationSpeaks';
import SocialValidation from './components/SocialValidation';
import FAQSection from './components/FAQSection';
import SecondCTA from './components/SecondCTA';
import FooterBar from './components/FooterBar';
import ContactPage from './components/ContactPage';

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
        ReactGA.initialize(data.gaTrackingId);
        ReactGA.send({ hitType: "pageview", page: window.location.pathname + window.location.search });
      })
      .catch(error => {
        console.error('Error loading config:', error);
        setError(error.message);
      });
  }, []);

  if (error) {
    return <div>Error loading configuration: {error}</div>;
  }

  if (!config) {
    return <div>Loading...</div>;
  }

  return (
    <Router>
      <div className="App">
        <HeaderBar 
          header={config.header} 
          icon={config.icon} 
        />
        <Routes>
          <Route path="/" element={
            <>
              <LandingHeader
                title={config.title}
                description={config.description}
                buttonText={config.buttonText}
                buttonLink={config.contactPageLink}
                userReviews={config.userReviews}
                videoUrl={config.videoUrl}
                imageUrl={config.imageUrl}
              />
              <IndustryPainpoints
                title={config.painpointsTitle}
                painpoints={config.painpoints}
                contactFormOptions={config.contactFormOptions}
                shortParagraph={config.shortParagraph}
                domainName={config.domainName}
                contactFormLambdaUrl={config.contactFormLambdaUrl}
              />
              <TheAutomationSpeaks
                title={config.theAutomationSpeaksTitle}
                text={config.theAutomationSpeaksText}
                image={config.theAutomationSpeaksImage}
              />
              <HowItWorks
                title={config.howItWorksTitle}
                description={config.howItWorksDescription}
                steps={config.howItWorksSteps}
              />
              <SocialValidation
                title={config.socialValidationTitle}
                text={config.socialValidationText}
              />
              <FAQSection
                title={config.faqTitle}
                faqItems={config.faqItems}
              />
              <SecondCTA
                title={config.secondCtaTitle}
                testimonial={config.secondCtaTestimonial}
                buttonText={config.secondCtaButtonText}
                buttonLink={config.contactPageLink}
                users={config.secondCtaUsers}
              />
            </>
          } />
          <Route path={config.contactPageLink} element={
            <ContactPage
              contactFormOptions={config.contactFormOptions}
              domainName={config.domainName}
              contactFormLambdaUrl={config.contactFormLambdaUrl}
              calendlyUrl={config.calendlyUrl}
              title={config.contactPageTitle}
              blurb={config.contactPageBlurb}
              contactFormTitle={config.contactFormTitle}
              scheduleCallTitle={config.scheduleCallTitle}
            />
          } />
        </Routes>
        <FooterBar footerText={config.footerText} />
      </div>
    </Router>
  );
}

export default App;
