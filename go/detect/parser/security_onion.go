package parser

import (
	"fmt"
	"regexp"
)

var securityOnionRegexPattern1 = regexp.MustCompile(` {|} `)

var securityOnionRegexPattern2 = regexp.MustCompile(` `)

type SecurityOnionParser struct {
	Pattern1, Pattern2 *regexp.Regexp
}

func (s *SecurityOnionParser) Parse(line string) ([]ApiCall, error) {

	matches1 := s.Pattern1.Split(line, -1)
	if len(matches1) != 5 {
		return nil, fmt.Errorf("Error parsing")
	}

	matches2 := s.Pattern2.Split(matches1[4], -1)
	if len(matches2) != 10 {
		return nil, fmt.Errorf("Error parsing")
	}

	return []ApiCall{
		&JsonRpcApiCall{
			Method: "event_add",
			Params: []interface{}{
				"date", matches1[1],
				"srcip", matches2[0],
				"dstip", matches2[1],
				"events", map[string]interface{}{
					"suricata_event": matches1[3],
					"detect":         matches2[6],
				},
			},
		},
	}, nil
}

func NewSecurityOnionParser() Parser {
	return &SecurityOnionParser{
		Pattern1: securityOnionRegexPattern1.Copy(),
		Pattern2: securityOnionRegexPattern2.Copy(),
	}
}
