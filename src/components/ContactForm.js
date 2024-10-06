import React, { useState } from 'react';
import ReactGA from 'react-ga4';

const ContactForm = ({ options, domainName, lambdaUrl }) => {
  const [formData, setFormData] = useState({
    siteId: domainName, // Use the domain name as the site identifier
    name: '',
    email: '',
    company: '',
    message: '',
    interests: []
  });
  const [isLoading, setIsLoading] = useState(false);
  const [submitStatus, setSubmitStatus] = useState(null);

  const handleChange = (e) => {
    const { name, value, type, checked } = e.target;
    if (type === 'checkbox') {
      setFormData(prevState => ({
        ...prevState,
        interests: checked
          ? [...prevState.interests, value]
          : prevState.interests.filter(interest => interest !== value)
      }));
    } else {
      setFormData(prevState => ({
        ...prevState,
        [name]: value
      }));
    }
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setIsLoading(true);
    setSubmitStatus(null);

    try {
      const response = await fetch(lambdaUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(formData),
      });

      if (response.ok) {
        ReactGA.event({
          category: 'Form',
          action: 'Submit',
          label: 'Contact Form'
        });
        setFormData({ name: '', email: '', company: '', message: '', interests: [] });
        setSubmitStatus('success');
      } else {
        setSubmitStatus('error');
      }
    } catch (error) {
      console.error('Error submitting form:', error);
      setSubmitStatus('error');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <form onSubmit={handleSubmit} className="bg-white shadow-md rounded px-8 pt-6 pb-8 mb-4">
      <h3 className="text-2xl font-bold mb-4">Contact Us</h3>
      <div className="mb-4">
        <input
          className="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline"
          type="text"
          name="name"
          value={formData.name}
          onChange={handleChange}
          placeholder="Your Name"
          required
        />
      </div>
      <div className="mb-4">
        <input
          className="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline"
          type="email"
          name="email"
          value={formData.email}
          onChange={handleChange}
          placeholder="Your Email"
          required
        />
      </div>
      <div className="mb-4">
        <input
          className="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline"
          type="text"
          name="company"
          value={formData.company}
          onChange={handleChange}
          placeholder="Your Company"
        />
      </div>
      <div className="mb-4">
        <textarea
          className="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline"
          name="message"
          value={formData.message}
          onChange={handleChange}
          placeholder="Your Message"
          required
          rows="4"
        ></textarea>
      </div>
      <div className="mb-4">
        <p className="mb-2 font-bold">I'm interested in:</p>
        {options.map((option, index) => (
          <label key={index} className="block mb-2">
            <input
              type="checkbox"
              name="interests"
              value={option}
              checked={formData.interests.includes(option)}
              onChange={handleChange}
              className="mr-2"
            />
            {option}
          </label>
        ))}
      </div>
      <button
        type="submit"
        className="bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded focus:outline-none focus:shadow-outline"
        disabled={isLoading}
      >
        {isLoading ? 'Sending...' : 'Send Message'}
      </button>
      {submitStatus === 'success' && (
        <p className="text-green-500 mt-2">Form submitted successfully!</p>
      )}
      {submitStatus === 'error' && (
        <p className="text-red-500 mt-2">Error submitting form. Please try again.</p>
      )}
    </form>
  );
};

export default ContactForm;