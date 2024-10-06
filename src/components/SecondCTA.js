import React from 'react';
import { Link } from 'react-router-dom';

const SecondCTA = ({ title, testimonial, buttonText, buttonLink, users }) => {
  return (
    <div className="bg-gray-900 text-white py-8">
      <div className="container mx-auto px-4">
        <h2 className="text-4xl font-bold mb-4 text-center" dangerouslySetInnerHTML={{ __html: title }}></h2>
        <p className="text-lg text-center italic mb-4" dangerouslySetInnerHTML={{ __html: testimonial }}></p>
        <div className="flex justify-center">
        <Link to={buttonLink} className="inline-block">
          <button className="bg-blue-500 text-white text-xl px-4 py-2 rounded-2xl text-center hover:bg-blue-600 transition duration-300">
            <span dangerouslySetInnerHTML={{ __html: buttonText }}></span>
          </button>
        </Link>
        </div>
      </div>
    </div>
  );
}

export default SecondCTA;
