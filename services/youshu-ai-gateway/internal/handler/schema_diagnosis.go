package handler



import (

	"strings"



	"github.com/youshu/youshu-ai-gateway/internal/contract"

)



// SchemaDiagnosis reports ValidateDraft outcomes without changing its rules.

type SchemaDiagnosis struct {

	Passed                   bool

	TitleValid               bool

	BodyValid                bool

	AnswerValid              bool

	ArraysValid              bool

	EnumValid                bool

	KeyFactKindValid         bool

	KeyFactValueValid        bool

	WarningSeverityValid     bool

	ActionDestinationValid   bool

	InvalidEnumField         string

	InvalidEnumValue         string

	FailedRule               string

}



func DiagnoseSchema(d contract.AssistantAnswerDraftDTO) SchemaDiagnosis {

	enumDiag := DiagnoseEnumCompliance(d)

	diag := SchemaDiagnosis{

		TitleValid:             strings.TrimSpace(d.Title) != "",

		BodyValid:              strings.TrimSpace(d.Body) != "",

		AnswerValid:            strings.TrimSpace(d.Answer) != "",

		ArraysValid:            d.KeyFacts != nil &&

			d.Warnings != nil &&

			d.Actions != nil &&

			d.References != nil &&

			d.CitedFactKeys != nil &&

			d.Unknowns != nil,

		KeyFactKindValid:       enumDiag.KeyFactKindValid,

		KeyFactValueValid:      enumDiag.KeyFactValueValid,

		WarningSeverityValid:   enumDiag.WarningSeverityValid,

		ActionDestinationValid: enumDiag.ActionDestinationValid,

		InvalidEnumField:       enumDiag.InvalidEnumField,

		InvalidEnumValue:       enumDiag.InvalidEnumValue,

		EnumValid:              enumDiag.AllValid(),

	}

	if err := ValidateDraft(d); err != nil {

		diag.FailedRule = err.Error()

		diag.Passed = false

		return diag

	}

	diag.Passed = true

	return diag

}


