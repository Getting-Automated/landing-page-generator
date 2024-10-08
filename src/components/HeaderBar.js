import React from 'react';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { library } from '@fortawesome/fontawesome-svg-core';
import { faMoneyBill } from '@fortawesome/free-solid-svg-icons';

library.add(faMoneyBill);

const HeaderBar = ({ header, icon }) => {
  return (
    <div className="bg-gray-800 text-white py-2 px-4">
      <div className="container mx-auto text-left flex items-center">
        <h1 className="text-2xl font-bold">{header}</h1>
        {icon && <FontAwesomeIcon icon={['fas', icon]} className="ml-2 text-2xl" />}
      </div>
    </div>
  );
}

export default HeaderBar;
