
// LabManagerConfigList.java --
//
// LabManagerConfigList.java is part of ElectricCommander.
//
// Copyright (c) 2005-2010 Electric Cloud, Inc.
// All rights reserved.
//

package ecplugins.labmanager.client;

import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;

import com.google.gwt.user.client.ui.ListBox;
import com.google.gwt.xml.client.Document;
import com.google.gwt.xml.client.Node;
import com.google.gwt.xml.client.XMLParser;

import static com.electriccloud.commander.gwt.client.util.XmlUtil.getNodeByName;
import static com.electriccloud.commander.gwt.client.util.XmlUtil.getNodeValueByName;
import static com.electriccloud.commander.gwt.client.util.XmlUtil.getNodesByName;

public class LabManagerConfigList
{

    //~ Instance fields --------------------------------------------------------

    private final Map<String, LabManagerConfigInfo> m_configInfo =
        new TreeMap<String, LabManagerConfigInfo>();

    //~ Methods ----------------------------------------------------------------

    public void addConfig(
            String configName,
            String configServer,
            String configPort)
    {
        m_configInfo.put(configName, new LabManagerConfigInfo(configServer, configPort));
    }

    public String parseResponse(String cgiResponse)
    {
        Document document     = XMLParser.parse(cgiResponse);
        Node     responseNode = getNodeByName(document, "response");
        String   error        = getNodeValueByName(responseNode, "error");

        if (error != null && !error.isEmpty()) {
            return error;
        }

        Node       configListNode = getNodeByName(responseNode, "cfgs");
        List<Node> configNodes    = getNodesByName(configListNode, "cfg");

        for (Node configNode : configNodes) {
            String configName   = getNodeValueByName(configNode, "name");
            String configServer = getNodeValueByName(configNode, "server");
            String configPort = getNodeValueByName(configNode, "port");

            addConfig(configName, configServer, configPort);
        }

        return null;
    }

    public void populateConfigListBox(ListBox lb)
    {

        for (String configName : m_configInfo.keySet()) {
            lb.addItem(configName);
        }
    }

    public Set<String> getConfigNames()
    {
        return m_configInfo.keySet();
    }

    public String getConfigServer(String configName)
    {
        return m_configInfo.get(configName).m_server;
    }

    public String getConfigPort(String configName)
    {
        return m_configInfo.get(configName).m_port;
    }

    public String getEditorDefinition(String configName)
    {
        return "EC-LabManager";
    }

    public boolean isEmpty()
    {
        return m_configInfo.isEmpty();
    }

    public void setEditorDefinition(
            String configServer,
            String editorDefiniton)
    {
    }

    //~ Inner Classes ----------------------------------------------------------

    private class LabManagerConfigInfo
    {

        //~ Instance fields ----------------------------------------------------

        private String m_server;
        private String m_port;

        //~ Constructors -------------------------------------------------------

        public LabManagerConfigInfo(String server, String port)
        {
            m_server = server;
            m_port = port;
        }
    }
}
