import React from 'react';
import ContactForm from './ContactForm';

const IndustryPainpoints = ({ title, painpoints, contactFormOptions, shortParagraph, domainName, contactFormLambdaURL }) => {
  return (
    <section className="bg-gray-100 py-12">
      <div className="container mx-auto px-4">
        <h2 className="text-3xl font-bold mb-8">{title}</h2>
        <div className="flex flex-wrap -mx-4">
          <div className="w-full lg:w-2/3 px-4 mb-8 lg:mb-0">
            <ul className="list-disc pl-5 mb-8">
              {painpoints.map((point, index) => (
                <li key={index} className="mb-4 text-lg" dangerouslySetInnerHTML={{ __html: point }} />
              ))}
            </ul>
            <p className="mb-8 text-lg" dangerouslySetInnerHTML={{ __html: shortParagraph }} />
          </div>
          <div className="w-full lg:w-1/3 px-4">
            <ContactForm 
              options={contactFormOptions} 
              domainName={domainName} 
              lambdaUrl={contactFormLambdaURL}
            />
          </div>
        </div>
      </div>
    </section>
  );
};

export default IndustryPainpoints;