"use client";

import { useState, type FormEvent } from "react";

export default function NewsletterForm() {
  const [message, setMessage] = useState("");
  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setMessage("Newsletter sign-up is coming soon. Please check back.");
  }
  return (
    <form action="#" onSubmit={handleSubmit}>
      <label className="sr-only" htmlFor="email">Email address</label>
      <input id="email" type="email" placeholder="Your email address" required />
      <button type="submit">Join us →</button>
      <small>By subscribing, you agree to receive email updates from MME.</small>
      {message ? <small role="status">{message}</small> : null}
    </form>
  );
}
