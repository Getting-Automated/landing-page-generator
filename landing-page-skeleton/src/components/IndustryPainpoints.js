import React, { useEffect } from 'react';

const IndustryPainpoints = ({ title, painpoints }) => {
  useEffect(() => {
    const script = document.createElement('script');
    script.src = "https://tally.so/widgets/embed.js";
    script.async = true;
    document.body.appendChild(script);

    script.onload = () => {
      if (typeof window.Tally !== 'undefined') {
        window.Tally.loadEmbeds();
      } else {
        document.querySelectorAll("iframe[data-tally-src]:not([src])").forEach((e) => {
          e.src = e.dataset.tallySrc;
        });
      }
    };

    return () => {
      document.body.removeChild(script);
    };
  }, []);

  return (
    <div className="bg-gray-100 text-gray-900 py-8">
      <div className="container mx-auto pr-2 flex flex-col md:flex-row justify-between items-start">
        <div className="md:w-2/3 mb-8 md:mb-0">
          <h2 className="text-2xl font-bold mb-4 text-left pr-4" dangerouslySetInnerHTML={{ __html: title }}></h2>
          <ul className="list-disc list-inside text-lg text-left">
            {painpoints.map((painpoint, index) => (
              <li key={index} dangerouslySetInnerHTML={{ __html: painpoint }}></li>
            ))}
          </ul>
        </div>
        <div className="md:w-1/3">
          <iframe 
            data-tally-src="https://tally.so/embed/w88zjO?alignLeft=1&hideTitle=1&transparentBackground=1&dynamicHeight=1" 
            loading="lazy" 
            width="100%" 
            height="552" 
            frameBorder="0" 
            marginHeight="0" 
            marginWidth="0" 
            title="Want us to help you?"
          ></iframe>
        </div>
      </div>
    </div>
  );
}

export default IndustryPainpoints;
