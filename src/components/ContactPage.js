import React, { useState } from 'react';
import ContactForm from './ContactForm';

const ContactPage = ({ 
  contactFormOptions, 
  domainName, 
  contactFormLambdaUrl, 
  calendlyUrl, 
  title,
  blurb,
  contactFormTitle,
  scheduleCallTitle
}) => {
  const [formSubmitted, setFormSubmitted] = useState(false);

  return (
    <div className="bg-gray-100 min-h-screen py-12">
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
                  lambdaUrl={contactFormLambdaUrl}
                  onSubmitSuccess={() => setFormSubmitted(true)}
                />
              )}
            </div>
            <div className="w-full md:w-1/2">
              <h2 className="text-2xl font-semibold mb-4">{scheduleCallTitle}</h2>
              <div className="calendly-embed-container" style={{ minWidth: '320px', height: '630px' }}>
                <iframe
                  src={calendlyUrl}
                  width="100%"
                  height="100%"
                  frameBorder="0"
                  title="Schedule a call with us"
                ></iframe>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default ContactPage;