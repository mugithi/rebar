package engine

/*
Copyright (c) 2016, Rackn Inc.
Licensed under the terms of the Digital Rebar License.
See LICENSE.md at the top of this repository for more information.
*/

import (
	"bytes"
	"fmt"
	"log"
	"os"
	"os/exec"
	"text/template"
)

func compileScript(script string) (*template.Template, error) {
	res := template.New("script").Option("missingkey=error")
	return res.Parse(script)
}

func runScript(c *RunContext, scriptTmpl *template.Template) (bool, error) {
	buf := &bytes.Buffer{}
	if err := scriptTmpl.Execute(buf, c); err != nil {
		return false, err
	}

	cmd := exec.Command("/usr/bin/env", "bash", "-x")

	cmd.Env = os.Environ()
	for k, v := range c.Engine.scriptEnv {
		cmd.Env = append(cmd.Env, fmt.Sprintf("%s=%s", k, v))
	}
	cmd.Stdin = buf
	out, err := cmd.Output()
	if err == nil {
		log.Printf("Ruleset %s: Script rule %d ran successfully", c.ruleset.Name, c.ruleIdx)
		log.Printf("%s", string(out))
		return true, nil
	}
	log.Printf("Ruleset %s: Script rule %d failed", c.ruleset.Name, c.ruleIdx)
	exitErr, ok := err.(*exec.ExitError)
	if ok {
		log.Printf("%s", string(exitErr.Stderr))
		return false, nil
	}
	log.Printf("Failed with error %v", err)
	return false, err
}
