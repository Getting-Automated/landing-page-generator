import React, { useState } from 'react';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { faChevronDown, faChevronUp } from '@fortawesome/free-solid-svg-icons';

const FAQSection = ({ title, faqItems }) => {
  const [activeIndex, setActiveIndex] = useState(null);

  const toggleAccordion = index => {
    setActiveIndex(activeIndex === index ? null : index);
  };

  return (
    <div className="bg-white text-gray-900 py-8">
      <div className="container mx-auto px-4">
        <h2 className="text-2xl font-bold mb-4" dangerouslySetInnerHTML={{ __html: title }}></h2>
        <div className="accordion">
          {faqItems.map((item, index) => (
            <div key={index} className="mb-4">
              <button
                className="w-full text-left p-4 bg-white border border-gray-300 rounded-lg focus:outline-none flex justify-between items-center"
                onClick={() => toggleAccordion(index)}
              >
                <h3 className="text-xl font-bold" dangerouslySetInnerHTML={{ __html: item.question }}></h3>
                <FontAwesomeIcon icon={activeIndex === index ? faChevronUp : faChevronDown} />
              </button>
              {activeIndex === index && (
                <div className="p-4 bg-white border border-gray-300 rounded-lg mt-2">
                  <p className="text-lg" dangerouslySetInnerHTML={{ __html: item.answer }}></p>
                </div>
              )}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

export default FAQSection;
