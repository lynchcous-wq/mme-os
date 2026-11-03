import { Suspense } from "react";
import LoginForm from "./LoginForm";

export default function EmployeeLoginPage() {
  return (
    <Suspense fallback={<main style={{ minHeight: "100vh", display: "grid", placeItems: "center" }}>Loading employee sign-in…</main>}>
      <LoginForm />
    </Suspense>
  );
}
