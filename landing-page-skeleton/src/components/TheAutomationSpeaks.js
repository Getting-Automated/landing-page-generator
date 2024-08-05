import React from 'react';

const TheAutomationSpeaks = ({ title, text, image }) => {
  return (
    <div className="bg-white text-gray-900 py-8">
      <div className="container mx-auto px-4 flex flex-col md:flex-row justify-between">
        <div className="md:w-2/3 mb-8 md:mb-0">
          <h2 className="text-4xl font-bold mb-4 text-left">{title}</h2>
          <p className="text-xl text-left pr-8">{text}</p>
        </div>
        <div className="md:w-1/3">
          <img className="rounded-lg shadow-lg" src={image} alt="Automation results" />
        </div>
      </div>
    </div>
  );
}

export default TheAutomationSpeaks;
