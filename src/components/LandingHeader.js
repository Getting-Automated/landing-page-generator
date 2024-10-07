import React, { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';

const LandingHeader = ({ title, description, buttonText, buttonLink, userReviews, videoUrl }) => {
  const [showVideo, setShowVideo] = useState(false);
  const [thumbnailUrl, setThumbnailUrl] = useState('');

  // Extract video ID from the URL
  const videoId = videoUrl.split('/').pop();

  useEffect(() => {
    // Fetch the maxresdefault thumbnail
    setThumbnailUrl(`https://img.youtube.com/vi/${videoId}/maxresdefault.jpg`);
  }, [videoId]);

  const handlePlayClick = () => {
    setShowVideo(true);
  };

  return (
    <header className="bg-gray-900 text-white py-8">
      <div className="container mx-auto flex flex-col md:flex-row justify-between items-center">
        <div className="md:w-1/2 mb-8 md:mb-0 pr-2">
          <h1 className="text-5xl font-bold mb-4 mr-4 text-left" dangerouslySetInnerHTML={{ __html: title }}></h1>
          <p className="text-lg mb-4 text-left" dangerouslySetInnerHTML={{ __html: description }}></p>
          <Link to={buttonLink} className="inline-block">
            <button className="bg-blue-500 text-white text-xl px-4 py-2 rounded-2xl text-center hover:bg-blue-600 transition duration-300">
              {buttonText}
            </button>
          </Link>
          <div className="mt-4 flex items-center">
          </div>
        </div>
        <div className="md:w-1/2 flex flex-col justify-center items-center p-4">
          <div className="relative w-full" style={{ paddingBottom: '56.25%' }}>
            {showVideo ? (
              <iframe
                className="absolute top-0 left-0 w-full h-full rounded-lg"
                src={`${videoUrl}?autoplay=1`}
                title="Automation for Staffing Demo Video"
                frameBorder="0"
                allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                allowFullScreen
                loading="lazy"
              ></iframe>
            ) : (
              <img 
                src={thumbnailUrl}
                alt="Video thumbnail"
                className="absolute top-0 left-0 w-full h-full rounded-lg cursor-pointer object-cover"
                onClick={handlePlayClick}
                width="640"
                height="360"
                loading="lazy"
              />
            )}
            {!showVideo && (
              <div className="absolute inset-0 flex items-center justify-center" onClick={handlePlayClick}>
                <svg className="w-20 h-20 text-white opacity-75 hover:opacity-100 transition-opacity duration-300" fill="currentColor" viewBox="0 0 20 20">
                  <path d="M4 4l12 6-12 6z" />
                </svg>
              </div>
            )}
          </div>
          <p className="mt-2">Don't just take our word for it</p>
        </div>
      </div>
    </header>
  );
}

export default LandingHeader;
