import { useTranslation } from 'react-i18next'
import { Card, InfoIcon } from '../../components/ui/index.js'

// Provider > Overview > a patient (route /provider/patient/:patientId).
// A clearly labelled PLACEHOLDER until step 4.3. It shows NO patient data: no name,
// no label, no id, no readings, and the address is not read. It writes no audit row,
// because nothing about the patient is opened here. Step 4.3 will write the
// "patient record opened" audit entry before it shows anything.
export default function PatientDetailPlaceholder() {
  const { t } = useTranslation()
  return (
    <Card title={t('provider:overview.placeholder.title')} className="nl-ov__card">
      <p className="nl-ov__empty-line">
        <InfoIcon size={18} />
        <span>{t('provider:overview.placeholder.body')}</span>
      </p>
    </Card>
  )
}
