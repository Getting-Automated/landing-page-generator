import React from 'react';

const HowItWorks = ({ title, description, steps }) => {
  return (
    <div className="bg-gray-100 text-gray-900 py-8">
      <div className="container mx-auto px-4">
        <h2 className="text-4xl font-bold mb-4 text-left">{title}</h2>
        <p className="text-xl mb-4 text-left">{description}</p>
        <ul className="list-disc list-inside text-left">
          {steps.map((step, index) => (
            <li key={index} className="text-2xl mb-2">{step}</li>
          ))}
        </ul>
      </div>
    </div>
  );
}

export default HowItWorks;
