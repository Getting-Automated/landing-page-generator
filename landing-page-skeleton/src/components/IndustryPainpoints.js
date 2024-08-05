import React from 'react';

const IndustryPainpoints = ({ title, painpoints, contactFormOptions, shortParagraph }) => {
  return (
    <div className="bg-gray-100 text-gray-900 py-8">
      <div className="container mx-auto pr-2 flex flex-col md:flex-row justify-between items-start">
        <div className="md:w-2/3 mb-8 md:mb-0">
          <h2 className="text-4xl font-bold mb-4 text-left pr-4">{title}</h2>
          <ul className="list-disc list-inside text-2xl text-left">
            {painpoints.map((painpoint, index) => (
              <li key={index}>{painpoint}</li>
            ))}
          </ul>
          <p className="text-3xl mt-4 text-left pr-6">{shortParagraph}</p>
        </div>
        <div className="md:w-1/3 bg-white p-4 rounded-lg shadow-lg">
          <h3 className="text-xl font-bold mb-4">Want us to do it for you too?</h3>
          <form className="text-left">
            <div className="mb-4">
              <label className="block text-sm font-bold mb-2" htmlFor="name">Name</label>
              <input className="w-full p-2 border rounded-lg" type="text" id="name" name="name" />
            </div>
            <div className="mb-4">
              <label className="block text-sm font-bold mb-2" htmlFor="email">Email</label>
              <input className="w-full p-2 border rounded-lg" type="email" id="email" name="email" />
            </div>
            <div className="mb-4">
              <label className="block text-sm font-bold mb-2" htmlFor="option">I want help with</label>
              <select className="w-full p-2 border rounded-lg" id="option" name="option">
                {contactFormOptions.map((option, index) => (
                  <option key={index} value={option}>{option}</option>
                ))}
              </select>
            </div>
            <div className="mb-4">
              <label className="block text-sm font-bold mb-2" htmlFor="message">Message</label>
              <textarea className="w-full p-2 border rounded-lg" id="message" name="message"></textarea>
            </div>
            <button className="bg-blue-500 text-white px-4 py-2 rounded-lg">Submit</button>
          </form>
        </div>
      </div>
    </div>
  );
}

export default IndustryPainpoints;
