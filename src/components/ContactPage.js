import React, { useState, useEffect, useRef } from 'react';
import ContactForm from './ContactForm';

const ContactPage = ({ 
  contactFormOptions, 
  domainName, 
  contactFormLambdaURL,
  calendlyUrl, 
  title,
  blurb,
  contactFormTitle,
  scheduleCallTitle
}) => {
  const [formSubmitted, setFormSubmitted] = useState(false);
  const [calendlyLoaded, setCalendlyLoaded] = useState(false);
  const calendlyRef = useRef(null);

  useEffect(() => {
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting && !calendlyLoaded) {
          const script = document.createElement('script');
          script.src = 'https://assets.calendly.com/assets/external/widget.js';
          script.async = true;
          script.onload = () => setCalendlyLoaded(true);
          document.body.appendChild(script);
        }
      },
      { rootMargin: '200px' } // Load when within 200px of viewport
    );

    if (calendlyRef.current) {
      observer.observe(calendlyRef.current);
    }

    return () => observer.disconnect();
  }, [calendlyLoaded]);

  console.log('ContactPage received lambdaUrl:', contactFormLambdaURL);

  return (
    <div className="bg-white min-h-screen py-12">
      <div className="container mx-auto px-4">
        <h1 className="text-4xl font-bold mb-4 text-center">{title}</h1>
        <p className="text-xl text-center mb-8">
          {blurb}
        </p>
        <div className="max-w-6xl mx-auto bg-white p-8 rounded-lg shadow-md">
          <div className="flex flex-col md:flex-row gap-8">
            <div className="w-full md:w-1/2">
              <h2 className="text-2xl font-semibold mb-4">{contactFormTitle}</h2>
              {formSubmitted ? (
                <div className="text-center text-green-600">
                  <p className="text-xl font-semibold">Thank you for your message!</p>
                  <p>We'll get back to you as soon as possible.</p>
                </div>
              ) : (
                <ContactForm
                  options={contactFormOptions}
                  domainName={domainName}
                  lambdaUrl={contactFormLambdaURL}
                  onSubmitSuccess={() => setFormSubmitted(true)}
                />
              )}
            </div>
            <div className="w-full md:w-1/2">
              <h2 className="text-2xl font-semibold mb-4">{scheduleCallTitle}</h2>
              <div 
                ref={calendlyRef}
                className="calendly-inline-widget" 
                data-url={calendlyUrl}
                style={{ minWidth: '320px', height: '630px' }}
              >
                {!calendlyLoaded && <p>Loading scheduler...</p>}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default ContactPage;