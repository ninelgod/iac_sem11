import { AddLoanForm } from "@/components/add-loan-form"

export default function AddLoanPage() {
  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100 dark:from-gray-900 dark:to-gray-800 p-4 md:p-8">
      <div className="max-w-2xl mx-auto">
        <AddLoanForm />
      </div>
    </div>
  )
}
