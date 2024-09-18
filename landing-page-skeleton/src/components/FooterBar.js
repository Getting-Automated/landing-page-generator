import React from 'react';

const FooterBar = ({ footerText }) => {
  return (
    <div className="bg-black text-white py-4">
      <div className="container mx-auto text-center">
        <p dangerouslySetInnerHTML={{ __html: footerText }}></p>
      </div>
    </div>
  );
}

export default FooterBar;
