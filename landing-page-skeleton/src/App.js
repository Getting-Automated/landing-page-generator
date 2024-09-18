import React, { useState, useEffect } from 'react';
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

function App() {
  const [config, setConfig] = useState(null);

  useEffect(() => {
    fetch('/config.json')
      .then(response => response.json())
      .then(data => setConfig(data));
  }, []);

  if (!config) {
    return <div>Loading...</div>;
  }

  return (
    <div className="App">
      <HeaderBar 
        header={config.header} 
        icon={config.icon} 
        />
      <LandingHeader
        title={config.title}
        description={config.description}
        buttonText={config.buttonText}
        buttonLink={config.heroButtonLink}
        userReviews={config.userReviews}
        videoUrl={config.videoUrl}
        imageUrl={config.imageUrl}
      />
      <IndustryPainpoints
        title={config.painpointsTitle}
        painpoints={config.painpoints}
        contactFormOptions={config.contactFormOptions}
        shortParagraph={config.shortParagraph}
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
        users={config.secondCtaUsers}
      />
      <FooterBar footerText={config.footerText} />
    </div>
  );
}

export default App;
