import { EditLoanForm } from "@/components/edit-loan-form"

export default function EditLoanPage({ params }: { params: { id: string } }) {
  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100 dark:from-gray-900 dark:to-gray-800 p-4 md:p-8">
      <div className="max-w-4xl mx-auto">
        <EditLoanForm loanId={params.id} />
      </div>
    </div>
  )
}
