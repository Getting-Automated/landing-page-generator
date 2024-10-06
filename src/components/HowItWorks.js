import React from 'react';
import { FaSearch, FaPencilAlt, FaPlug, FaVial, FaUserGraduate, FaRocket } from 'react-icons/fa';

const icons = [FaSearch, FaPencilAlt, FaPlug, FaVial, FaUserGraduate, FaRocket];

const HowItWorks = ({ title, description, steps }) => {
  return (
    <section className="py-16 bg-gray-100">
      <div className="container mx-auto px-4">
        <h2 className="text-3xl font-bold mb-8 text-center">{title}</h2>
        <p className="mb-12 text-lg" dangerouslySetInnerHTML={{ __html: description }}></p>
        <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
          {steps.map((step, index) => {
            const Icon = icons[index % icons.length];
            return (
              <div key={index} className="bg-white p-6 rounded-lg shadow-md hover:shadow-lg transition-shadow duration-300">
                <div className="flex items-center mb-4">
                  <div className="bg-blue-500 text-white rounded-full p-3 mr-4">
                    <Icon className="w-6 h-6" />
                  </div>
                  <h3 className="text-xl font-semibold">Step {index + 1}</h3>
                </div>
                <div dangerouslySetInnerHTML={{ __html: step }}></div>
              </div>
            );
          })}
        </div>
      </div>
    </section>
  );
};

export default HowItWorks;
