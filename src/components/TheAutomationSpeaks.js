import React from 'react';

const TheAutomationSpeaks = ({ title, text, image }) => {
  return (
    <section className="bg-white text-gray-900 py-12">
      <div className="container mx-auto px-4">
        <div className="mb-8 overflow-hidden rounded-lg shadow-lg">
          <img 
            className="w-full h-64 md:h-96 object-cover" 
            src={image} 
            alt="Automation results" 
          />
        </div>
        <h2 className="text-3xl font-bold mb-6 text-center" dangerouslySetInnerHTML={{ __html: title }}></h2>
        <div className="prose prose-lg max-w-none text-lg" dangerouslySetInnerHTML={{ __html: text }}></div>
      </div>
    </section>
  );
}

export default TheAutomationSpeaks;
