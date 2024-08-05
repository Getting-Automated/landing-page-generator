import React from 'react';

const LandingHeader = ({ title, description, buttonText, userReviews, videoUrl }) => {
  return (
    <div className="bg-gray-900 text-white py-8">
      <div className="container mx-auto flex flex-col md:flex-row justify-between items-center">
        <div className="md:w-1/2 mb-8 md:mb-0 pr-2">
          <h1 className="text-6xl font-bold mb-4 text-left">{title}</h1>
          <p className="text-lg mb-4 text-left">{description}</p>
          <button className="bg-blue-500 text-white text-xl px-4 py-2 rounded-2xl text-center">{buttonText}</button>
          <div className="mt-4 flex items-center">
            <div className="flex -space-x-2">
              {userReviews.map((user, index) => (
                <img
                  key={index}
                  className="h-10 w-10 rounded-full border-2 border-white"
                  src={user.image}
                  alt={user.name}
                />
              ))}
            </div>
            <div className="ml-4">
              <div className="flex items-center">
                <div className="text-yellow-400 flex">
                  ★★★★★
                </div>
              </div>
              <p className="text-sm">(5/5 from 700+ users)</p>
            </div>
          </div>
        </div>
        <div className="md:w-1/2 flex flex-col justify-center items-center p-4">
          <div className="relative w-full" style={{ paddingBottom: '56.25%' }}>
            <iframe
              className="absolute top-0 left-0 w-full h-full rounded-lg"
              src={videoUrl}
              title="YouTube video"
              frameBorder="0"
              allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
              allowFullScreen
            ></iframe>
          </div>
          <p className="mt-2">Don't just take our word for it</p>
        </div>
      </div>
    </div>
  );
}

export default LandingHeader;
