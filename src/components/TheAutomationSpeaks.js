import React from 'react';

const TheAutomationSpeaks = ({ title, text, image }) => {
  return (
    <section className="py-16 bg-white">
      <div className="container mx-auto px-4">
        <h2 className="text-3xl font-bold mb-8 text-center">{title}</h2>
        <div className="flex flex-col items-center">
          <div className="w-2/3 mb-8">
            <img 
              src={`${process.env.PUBLIC_URL}${image}`} 
              alt="Staffing Workflow" 
              className="w-full h-auto object-contain rounded-lg shadow-md"
            />
          </div>
          <div className="w-full">
            <p className="text-lg mb-4" dangerouslySetInnerHTML={{ __html: text }}></p>
          </div>
        </div>
      </div>
    </section>
  );
};

export default TheAutomationSpeaks;
