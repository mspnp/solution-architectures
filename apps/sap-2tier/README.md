# SAP NetWeaver 2-tier compatible template using a Marketplace image

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fgithub.com%2FAzure%2Ffta-wip%2Fblob%2Fmaster%2FSAP%2Ftemplates%2Fsap-2tier%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>
<a href="http://armviz.io/#/?load=https%3A%2F%2Fgithub.com%2FAzure%2Ffta-wip%2Fblob%2Fmaster%2FSAP%2Ftemplates%2Fsap-2tier%2Fazuredeploy.json" target="_blank">
    <img src="http://armviz.io/visualizebutton.png"/>
</a>

This template takes a minimum amount of parameters and deploys a VM that is customized for use with SAP NetWeaver, using the latest patched version of the selected operating system. 
This is a template for a 2-tier configuration. It deploys 1 server on Premium Storage.
This template uses Managed Disks.

There is not suitable configuration for X-Large with Standard Storage. If you select this configuration, the template will deploy a Large configuration.

<table>
	<tr>
		<th>Size</th>
		<th>Premium Storage</th>
	</tr>
	<tr>
		<td>Small < 8.000 SAPS</td>
		<td>1xD8s_v3 (2xP20 1xP10)</td>
	</tr>
	<tr>
		<td>Medium < 16.000 SAPS</td>
		<td>1xD16s_v3 (3xP20 1xP10)</td>
	</tr>
	<tr>
		<td>Large < 32.000 SAPS</td>
		<td>1xE32s_v3 (3xP20 + 1xP20)</td>
	</tr>
	<tr>
		<td>X-Large < 64.000 SAPS</td>
		<td>1xM64s (4xP20 1xP20)</td>
	</tr>
</table>				