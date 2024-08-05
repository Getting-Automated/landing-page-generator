import React from 'react';

const SocialValidation = ({ title, text }) => {
  return (
    <div className="bg-white text-gray-900 py-8">
      <div className="container mx-auto px-4">
        <h2 className="text-4xl font-bold mb-4">{title}</h2>
        <p className="text-xl mb-4">{text}</p>
        {/* Add more content or testimonials as needed */}
      </div>
    </div>
  );
}

export default SocialValidation;
