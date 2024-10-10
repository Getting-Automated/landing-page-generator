import React, { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';

const LandingHeader = ({ title, description, buttonText, buttonLink, userReviews, videoUrl }) => {
  const [loaded, setLoaded] = useState(false);
  const [showVideo, setShowVideo] = useState(false);
  const [thumbnailUrl, setThumbnailUrl] = useState('');

  // Extract video ID from the URL
  const videoId = videoUrl.split('/').pop();

  useEffect(() => {
    // Use a smaller thumbnail for mobile devices
    const thumbnailSize = window.innerWidth < 768 ? 'hqdefault' : 'hqdefault';
    setThumbnailUrl(`https://img.youtube.com/vi/${videoId}/${thumbnailSize}.jpg`);
    setLoaded(true);
  }, [videoId]);

  const handlePlayClick = () => {
    setShowVideo(true);
  };

  if (!loaded) {
    return (
      <header className="bg-gray-900 text-white py-8">
        <div className="container mx-auto flex flex-col md:flex-row justify-between items-center">
          <div className="md:w-1/2 mb-8 md:mb-0 pr-2">
            <div className="h-12 bg-gray-700 rounded mb-4 w-3/4"></div>
            <div className="h-4 bg-gray-700 rounded mb-2 w-full"></div>
            <div className="h-4 bg-gray-700 rounded mb-2 w-5/6"></div>
            <div className="h-4 bg-gray-700 rounded mb-4 w-4/5"></div>
            <div className="h-10 bg-blue-500 rounded w-40"></div>
          </div>
          <div className="md:w-1/2 flex flex-col justify-center items-center p-4">
            <div className="w-full bg-gray-700 rounded" style={{ paddingTop: '56.25%' }}></div>
          </div>
        </div>
      </header>
    );
  }

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
        </div>
        <div className="md:w-1/2 flex flex-col justify-center items-center p-4">
          <div className="video-container relative w-full" style={{ paddingTop: '56.25%' }}> {/* 16:9 aspect ratio */}
            {showVideo ? (
              <iframe
                className="absolute top-0 left-0 w-full h-full rounded-lg"
                src={`${videoUrl}?autoplay=1`}
                title="Automation for Staffing Demo Video"
                frameBorder="0"
                allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                allowFullScreen
              ></iframe>
            ) : (
              <img 
                src={thumbnailUrl}
                alt="Video thumbnail"
                className="absolute top-0 left-0 w-full h-full rounded-lg cursor-pointer object-cover"
                onClick={handlePlayClick}
                width="640"
                height="360"
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
