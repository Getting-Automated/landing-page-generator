import React from 'react';

const FooterBar = ({ footerText }) => {
  return (
    <div className="bg-black text-white py-4">
      <div className="container mx-auto text-center">
        <p>{footerText}</p>
      </div>
    </div>
  );
}

export default FooterBar;
