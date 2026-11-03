import { redirect } from "next/navigation";
import { createClient as createSessionClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

/** Employee authorization is checked server-side on every employee route render. */
export default async function EmployeeLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  // The login page must remain reachable without an employee relationship.
  // Middleware validates identity for employee routes; this layout protects workspace routes.
  const sessionClient = await createSessionClient();
  const { data: { user }, error: userError } = await sessionClient.auth.getUser();
  if (userError || !user) redirect("/employee/login");

  try {
    const admin = createAdminClient();
    const [{ data: employee, error: employeeError }, { data: settings, error: settingsError }] = await Promise.all([
      admin.from("employee_relationships").select("employment_status").eq("user_id", user.id).maybeSingle(),
      admin.from("employee_security_settings").select("employee_access_frozen,ceo_user_id").eq("singleton", true).maybeSingle(),
    ]);

    // Fail closed if either security record is missing or cannot be read.
    if (employeeError || settingsError || employee?.employment_status !== "active" || !settings || settings.employee_access_frozen || !settings.ceo_user_id) {
      redirect("/employee/access-denied");
    }
  } catch {
    // Missing service-role configuration, unapplied migrations, or query failure
    // must never grant employee access.
    redirect("/employee/access-denied?reason=configuration");
  }

  return <>{children}</>;
}
