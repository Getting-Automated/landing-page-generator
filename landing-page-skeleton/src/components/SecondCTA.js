import React from 'react';

const SecondCTA = ({ title, testimonial, buttonText, users }) => {
  return (
    <div className="bg-gray-900 text-white py-8">
      <div className="container mx-auto px-4">
        <div className="flex flex-wrap justify-center mb-4">
          {users.map((user, index) => (
            <img
              key={index}
              className="h-10 w-10 rounded-full border-2 border-white m-1"
              src={user.image}
              alt={`User ${index + 1}`}
            />
          ))}
        </div>
        <h2 className="text-4xl font-bold mb-4 text-center">{title}</h2>
        <p className="text-lg text-center italic mb-4">{testimonial}</p>
        <div className="flex justify-center">
          <button className="bg-blue-500 text-white px-4 py-2 rounded-lg">{buttonText}</button>
        </div>
      </div>
    </div>
  );
}

export default SecondCTA;
